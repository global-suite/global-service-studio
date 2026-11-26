import AppKit
import GSSLibrary

/// The launch arguments of the live measurement: `--measure-live <report.json> [--rounds N] [--pace SECONDS]`.
struct LiveMeasurementOptions: Equatable {
    struct Invalid: Error { let message: String }
    var report: URL
    var rounds = 3
    var pace = 1.5

    /// The options when the arguments hold `--measure-live`, nil when they do not; a missing or invalid value throws.
    static func parse(_ arguments: [String]) throws -> LiveMeasurementOptions? {
        guard let flag = arguments.firstIndex(of: "--measure-live") else { return nil }
        func value(_ name: String, at index: Int) throws -> String {
            guard arguments.indices.contains(index + 1), !arguments[index + 1].hasPrefix("--") else { throw Invalid(message: "\(name) needs a value") }
            return arguments[index + 1]
        }
        var options = LiveMeasurementOptions(report: URL(fileURLWithPath: try value("--measure-live", at: flag)))
        if let index = arguments.firstIndex(of: "--rounds") {
            guard let rounds = Int(try value("--rounds", at: index)), rounds > 0 else { throw Invalid(message: "--rounds needs a positive whole number") }
            options.rounds = rounds
        }
        if let index = arguments.firstIndex(of: "--pace") {
            guard let pace = Double(try value("--pace", at: index)), pace > 0 else { throw Invalid(message: "--pace needs a positive number of seconds") }
            options.pace = pace
        }
        return options
    }
}

/// A developer measurement of main-thread stalls during a live run (issue #157, docs/live-measurement.md). It drives the app only through
/// `AppState.perform(_:)`, as an operator would, times each command on the main thread, and runs the watchdog meanwhile.
/// Its console output is English only, like GSSVideoBench. It only runs when the app is launched with `--measure-live`.
@MainActor final class LiveMeasurement {
    private let state: AppState
    private let options: LiveMeasurementOptions
    private weak var operatorWindow: NSWindow?
    private let watchdog = MainThreadWatchdog()
    private var samples: [ActionSample] = []

    private init(state: AppState, options: LiveMeasurementOptions, operatorWindow: NSWindow?) {
        (self.state, self.options, self.operatorWindow) = (state, options, operatorWindow)
    }

    /// Starts a measurement when the launch arguments ask for one; nil, changing nothing, when they do not.
    static func startIfRequested(state: AppState, operatorWindow: NSWindow?, arguments: [String] = CommandLine.arguments) -> LiveMeasurement? {
        let options: LiveMeasurementOptions
        do { guard let parsed = try LiveMeasurementOptions.parse(arguments) else { return nil }; options = parsed } catch {
            fail((error as? LiveMeasurementOptions.Invalid)?.message ?? "\(error)")
        }
        let measurement = LiveMeasurement(state: state, options: options, operatorWindow: operatorWindow)
        Task { await measurement.run() }
        return measurement
    }

    private func run() async {
        while state.isLibraryLoading { try? await Task.sleep(for: .milliseconds(100)) }
        let folder = state.libraryFolder
        guard let inspected = await Task.detached(operation: { Self.inspect(folder) }).value else {
            Self.fail("no library at \(folder.path); choose the library in Settings first")
        }
        let (library, services) = inspected
        guard services > 0 else { Self.fail("the library has no dated service plan; save one first") }
        let started = DispatchTime.now().uptimeNanoseconds
        watchdog.start()
        perform("setMode(live)", .setMode(.live))
        var outputs: [String] = []
        for round in 1...options.rounds {
            perform("openLaunchService", .openLaunchService)
            guard !state.program.slides.isEmpty else { Self.fail("the most recent service has no slides") }
            await pause()
            if round == 1 { outputs = await showOutputs() }
            for _ in state.program.slides.indices {
                let next = state.programIndex + 1, newItem = state.program.slides.indices.contains(next) && state.program.slides[next].item != state.liveItem
                perform(newItem ? "nextSlide.newItem" : "nextSlide", .nextSlide)
                await pause()
            }
            perform("clearAll", .clearAll)
            await pause()
        }
        watchdog.stop()
        let report = LiveMeasurementReport(machine: .current(), library: library, rounds: options.rounds, pace: options.pace, slides: state.program.slides.count,
                                           outputs: outputs, samples: samples, stalls: watchdog.stalls,
                                           durationSeconds: Double(DispatchTime.now().uptimeNanoseconds - started) / 1e9)
        let url = options.report
        do { try await Task.detached { try report.json().write(to: url, options: .atomic) }.value } catch {
            Self.fail("the report could not be written to \(url.path): \(error.localizedDescription)")
        }
        print(report.table)
        print("report: \(url.path)")
        exit(0)
    }

    /// Shows the audience output on the display the Output menu would choose, and the key and stage outputs when a display is already chosen for them.
    private func showOutputs() async -> [String] {
        var shown: [String] = []
        if state.outputScreen == nil, let screen = defaultOutputScreen(screens: ScreenInfo.connected(), operatorScreenID: operatorWindow?.screen?.displayID,
                                                                       avoiding: [state.keyOutputScreen, state.stageOutputScreen]) {
            perform("selectOutputScreen", .selectOutputScreen(screen.id))
        }
        let outputs: [(String, ScreenID?, AppCommand)] = [("audience", state.outputScreen, .showAudienceOutput(true)),
                                                          ("key", state.keyOutputScreen, .showKeyOutput(true)), ("stage", state.stageOutputScreen, .showStageOutput(true))]
        for (name, screen, command) in outputs where screen != nil {
            perform("show\(name.capitalized)Output", command)
            shown.append(name)
            await pause()
        }
        if shown.isEmpty { FileHandle.standardError.write(Data("live measurement: only one display; no output is shown. Connect a second display.\n".utf8)) }
        return shown
    }

    /// Runs one command on the main thread, timed, with the watchdog's activity named after it until the next one.
    private func perform(_ action: String, _ command: AppCommand) {
        watchdog.setActivity(action)
        let start = DispatchTime.now().uptimeNanoseconds
        state.perform(command)
        samples.append(ActionSample(action: action, ms: Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6))
    }

    private func pause() async { try? await Task.sleep(for: .seconds(options.pace)) }

    /// The library's size and its number of dated services, read off the main thread; nil without a library.
    private nonisolated static func inspect(_ folder: URL) -> (LibrarySize, Int)? {
        guard Library.exists(at: folder), let library = try? Library.open(folder) else { return nil }
        let plans = (try? library.plans().plans) ?? []
        return (LibrarySize(songs: (try? library.songs().songs.count) ?? 0, presentations: (try? library.presentations().presentations.count) ?? 0, plans: plans.count),
                plans.filter { !$0.plan.isTemplate }.count)
    }

    private nonisolated static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("live measurement: \(message)\n".utf8))
        exit(1)
    }
}
