// GSSVideoBench measures heavy video playback on the slowest supported Mac before the media
// layer relies on it (ADR 0008). It is a developer tool: its console output is English only and
// it shares no code with the app. See docs/video-benchmark.md.
import AppKit

let usage = """
    usage:
      GSSVideoBench make-clips <dir> [--seconds N]
      GSSVideoBench play <file> [--outputs 1|2] [--seconds N] [--fullscreen]
      GSSVideoBench run-all <clipsDir> [--outputs 1|2] [--seconds N] [--fullscreen]
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else { fail(usage) }
let command = args[0], path = URL(fileURLWithPath: args[1])

/// The positive number after `name`, or `fallback` when the option is absent.
func number(_ name: String, _ fallback: Int) -> Int {
    guard let i = args.firstIndex(of: name) else { return fallback }
    guard i + 1 < args.count, let value = Int(args[i + 1]), value > 0 else { fail("\(name) needs a positive number") }
    return value
}

switch command {
case "make-clips":
    do { try ClipMaker.makeAll(in: path, seconds: number("--seconds", 20)) } catch { fail(error.localizedDescription) }
case "play", "run-all":
    let outputs = number("--outputs", command == "play" ? 1 : 2)
    guard outputs <= 2 else { fail("--outputs must be 1 or 2") }
    // run-all stays under the 20 s clips so the loop seam is not measured.
    let seconds = Double(number("--seconds", command == "play" ? 30 : 15))
    let files = command == "play" ? [path] : ((try? FileManager.default.contentsOfDirectory(
        at: path, includingPropertiesForKeys: nil)) ?? [])
        .filter { ["mp4", "mov", "m4v"].contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard !files.isEmpty else { fail("no video files at \(path.path)") }

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    guard !NSScreen.screens.isEmpty else { fail("no display available: playback needs a screen") }

    var results: [PlayResult] = []

    /// Plays the files one after another, then prints the table and one JSON line per file.
    @MainActor func playNext(_ remaining: ArraySlice<URL>) {
        guard let file = remaining.first else {
            print(PlayResult.header)
            results.forEach { print($0.row) }
            results.forEach { print($0.json) }
            exit(0)
        }
        print("playing \(file.lastPathComponent) on \(outputs) output(s) for \(Int(seconds)) s")
        do {
            let bench = try PlaybackBench(url: file, outputs: outputs, seconds: seconds,
                                          fullscreen: args.contains("--fullscreen")) { result in
                results.append(result)
                DispatchQueue.main.async { playNext(remaining.dropFirst()) }
            }
            bench.start()
        } catch {
            fail(error.localizedDescription)
        }
    }

    DispatchQueue.main.async {
        app.activate(ignoringOtherApps: true)
        playNext(files[...])
    }
    app.run()
default:
    fail(usage)
}
