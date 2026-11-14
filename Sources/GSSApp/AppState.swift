import Combine
import CoreGraphics
import Foundation
import GSSCore
import GSSLibrary

/// The two modes of the main window.
public enum AppMode: CaseIterable, Sendable {
    case prepare, live
}

/// A change to the app state; every change goes through a command (ADR 0006, rule 1).
public enum AppCommand: Equatable, Sendable {
    case setMode(AppMode)
    case nextSlide, previousSlide
    case goToSlide(Int)
    case clearSlide, clearAll
    case selectPart(Int)
    case setLines(sectionID: String, lines: [String])
    case showAudienceOutput(Bool)
    case selectOutputScreen(ScreenID?)
    /// Shows or hides the key output, like the audience output; a display holds one output, so choosing one moves the other output off it.
    case showKeyOutput(Bool)
    case selectKeyOutputScreen(ScreenID?)
    /// Sets the key color, saved in the settings; anything but `#RRGGBB` is ignored.
    case setKeyColor(String)
    /// Makes a song the one prepared, from its first part; a song without slides is ignored. It never changes what is on air.
    case loadSong(Song)
    /// Makes a plan the program, with the songs its items refer to; nothing is on air until Next or a slide click.
    case openPlan(Plan, songs: [Song])
    /// Shows a plan item's slides in the Live grid without putting them on air; nil or the live item returns to it, an item without slides is ignored.
    case previewItem(Int?)
    /// Adds a song file of the library to the plan, after the live item or at the end; it never goes on air by itself.
    case addToService(URL, position: ServicePosition)
    /// Edits the order of the default arrangement: a part moves to a final position, a section is inserted (repeated) at a position,
    /// a part leaves the order (never the last one), or a new section of a kind is created at a position. Invalid indexes are ignored.
    case moveArrangementItem(from: Int, to: Int)
    case insertArrangementItem(sectionID: String, at: Int)
    case removeArrangementItem(at: Int)
    case addSection(kind: SongSectionKind, at: Int)
    /// Chooses how Live shows repeated parts, saved in the settings; the live slide stays on the same part.
    case setRepetitionMode(RepetitionMode)
    /// Makes a folder the library, creating its layout when the folder is empty, and saves it in the settings; a refused folder is reported in `alert`.
    case chooseLibraryFolder(URL)
    /// Saves the current song in the library, creating the library the first time; a failure is reported in `alert`.
    case saveSong
    /// Opens the most recently modified song of the library when the folder holds one; never creates the library.
    case openMostRecentSong
    /// Opens the search index of the library folder off the main thread, reconciles it with the files, then lists its songs; never creates the library.
    case openLibraryIndex
    /// Filters the library list: songs whose words start with the words of the text, ignoring case and accents; every song when it has none.
    case setLibrarySearch(String)
    /// Opens a song file of the library; a file that cannot be read is reported in `alert`.
    case openLibrarySong(URL)
    /// Sets the background of the media layer; a color that is not `#RRGGBB` or a file that is not a readable image or video is ignored.
    /// An image is decoded here, and a video prepared, before it shows.
    case setBackground(Background)
    /// Takes the background off and leaves the slide.
    case clearBackground
}

/// A file of the library the list cannot show, with the localized reason.
public struct LibraryProblem: Equatable, Sendable {
    public let file, reason: String
}

/// A failure the window shows to the operator, already localized.
public struct AppAlert: Equatable, Sendable {
    public let title, message: String
}

/// A display, by its Core Graphics display ID.
public typealias ScreenID = UInt32

/// The state the interface shows, changed only by `perform(_:)`.
public final class AppState: ObservableObject {
    @Published public private(set) var mode: AppMode = .prepare
    /// The live slide within `slides` when the live item shows exactly the prepared song's slides, else -1.
    @Published public private(set) var liveIndex = 0
    /// The plan Live runs, with its songs and slides; nothing else goes on air.
    @Published public private(set) var program: Program
    /// The live slide, an index into `program.slides`; -1 before the first slide, with nothing on air.
    @Published public private(set) var programIndex = 0
    /// The plan item the Live grid previews, not on air; nil follows the live item.
    @Published public private(set) var previewItem: Int?
    @Published public private(set) var isCleared = false
    @Published public private(set) var song: Song
    @Published public private(set) var parts: [SongPart]
    @Published public private(set) var slides: [LiveSlide]
    /// The part being edited in Prepare mode, as an index into `parts`.
    @Published public private(set) var selectedPart = 0
    /// Whether the audience output covers its display; only with a display chosen.
    @Published public private(set) var isAudienceOutputShown = false
    /// The display chosen for the audience output.
    @Published public private(set) var outputScreen: ScreenID?
    /// Whether the key output covers its display; only with a display chosen.
    @Published public private(set) var isKeyOutputShown = false
    /// The display chosen for the key output.
    @Published public private(set) var keyOutputScreen: ScreenID?
    /// The color behind the words on the key output, as `#RRGGBB`.
    @Published public private(set) var keyColor: String
    /// How Live shows repeated parts.
    @Published public private(set) var repetitionMode: RepetitionMode
    /// The library folder songs are saved to.
    @Published public private(set) var libraryFolder: URL
    /// The songs of the library that match `librarySearch`: by title, or best match first while searching.
    @Published public private(set) var librarySongs: [SongMatch] = []
    @Published public private(set) var librarySearch = ""
    /// Invalid files and files that share a song `id`, by file name.
    @Published public private(set) var libraryProblems: [LibraryProblem] = []
    /// Whether the index is being opened and reconciled off the main thread.
    @Published public private(set) var isLibraryLoading = false
    /// The last failure to show, set again for every new one.
    @Published public private(set) var alert: AppAlert?
    /// Where settings changes are saved; nil keeps them in memory.
    private let settings: AppSettings?
    /// Where the index of a library is kept; nil keeps no index and the list empty.
    private let indexURL: ((Library) throws -> URL)?
    /// The serial queue every index load runs on, so two loads never open the same index file at once.
    private let indexQueue: DispatchQueue
    private var index: LibraryIndex?
    private var invalidFiles: [LibraryProblem] = []
    /// Counts index loads, so a load that finishes after the library changed is dropped.
    private var libraryLoads = 0

    /// The library file the current song was opened from or saved to; nil for a song from elsewhere.
    @Published public private(set) var openSongFile: URL?

    /// The background of the media layer, which slide changes and Clear Slide leave alone.
    @Published public private(set) var background: Background = .none
    /// The decoded image of an image background, set before `background` is published.
    public private(set) var backgroundImage: CGImage?
    /// The player of a video background, prepared before `background` is published and stopped when the background changes.
    private(set) var backgroundVideo: BackgroundVideo?
    /// A video background being prepared; it shows when ready unless another background is chosen first.
    private var pendingVideo: BackgroundVideo?

    public init(settings: AppSettings? = nil, indexURL: ((Library) throws -> URL)? = nil, indexQueue: DispatchQueue = DispatchQueue(label: "GSS library index")) {
        (self.indexURL, self.indexQueue) = (indexURL, indexQueue)
        let mode = settings?.repetitionMode ?? .separateSlides, parts = SongPart.parts(of: SampleSong.song, mode: mode)
        (song, self.parts, slides, repetitionMode, self.settings) = (SampleSong.song, parts, parts.flatMap(\.slides), mode, settings)
        // A plan with the sample song, run until a plan is opened.
        program = Program(plan: Plan(title: "Sample", items: [PlanItem(id: "sample", kind: .song, song: SampleSong.song.id)]), songs: [SampleSong.song.id: SampleSong.song], mode: mode)
        libraryFolder = settings?.libraryFolder ?? AppSettings.defaultLibraryFolder
        keyColor = settings?.keyColor ?? KeyColor.green.hex
        selectedPart = livePart
    }

    /// The part of the prepared song that holds the live slide, or -1 when it is not on air.
    public var livePart: Int { liveIndex < 0 ? -1 : part(containing: liveIndex) }
    /// The part that holds a slide of the song.
    public func part(containing slide: Int) -> Int { parts.firstIndex { $0.slideRange.contains(slide) } ?? 0 }

    /// Whether a slide of the program is live.
    public var isOnAir: Bool { program.slides.indices.contains(programIndex) }
    /// The plan item of the live slide.
    public var liveItem: Int? { isOnAir ? program.slides[programIndex].item : nil }
    /// The plan item Next goes to after the live item's slides.
    public var nextItem: Int? { program.slides.dropFirst(liveItem.map { program.range(of: $0).upperBound } ?? 0).first?.item }
    /// The live slide of the program; a blank one when nothing is on air.
    public var liveSlide: LiveSlide { isOnAir ? program.slides[programIndex].slide : LiveSlide(section: "", part: 0, partCount: 0, lines: []) }
    public var nextSlide: LiveSlide? { program.slides.indices.contains(programIndex + 1) ? program.slides[programIndex + 1].slide : nil }
    public var previousSlide: LiveSlide? { programIndex > 0 ? program.slides[programIndex - 1].slide : nil }
    /// The lines the outputs show: none while cleared.
    public var shownLines: [String] { isCleared ? [] : liveSlide.lines }

    /// Applies a command; moves outside the song and words that leave a part empty are ignored, other moves end a clear. Clear All also clears the background.
    /// The audience output shows only with a display chosen, and clearing the display hides it.
    public func perform(_ command: AppCommand) {
        switch command {
        case .setMode(let mode): if mode != self.mode { self.mode = mode }
        case .nextSlide: goToSlide(programIndex + 1)
        case .previousSlide: goToSlide(programIndex - 1)
        case .goToSlide(let index): goToSlide(index)
        case .clearSlide: if !isCleared { isCleared = true }
        case .clearAll:
            if !isCleared { isCleared = true }
            setBackground(.none)
        case .selectPart(let index): if parts.indices.contains(index), index != selectedPart { selectedPart = index }
        case .setLines(let sectionID, let lines): setLines(sectionID, lines)
        case .showAudienceOutput(let shown): if shown != isAudienceOutputShown, !shown || outputScreen != nil { isAudienceOutputShown = shown }
        case .selectOutputScreen(let screen):
            if screen == nil, isAudienceOutputShown { isAudienceOutputShown = false }
            if screen != nil, screen == keyOutputScreen { perform(.selectKeyOutputScreen(nil)) }
            if screen != outputScreen { outputScreen = screen }
        case .showKeyOutput(let shown): if shown != isKeyOutputShown, !shown || keyOutputScreen != nil { isKeyOutputShown = shown }
        case .selectKeyOutputScreen(let screen):
            if screen == nil, isKeyOutputShown { isKeyOutputShown = false }
            if screen != nil, screen == outputScreen { perform(.selectOutputScreen(nil)) }
            if screen != keyOutputScreen { keyOutputScreen = screen }
        case .setKeyColor(let value):
            guard let color = KeyColor(hex: value) else { return }
            settings?.keyColor = color.hex
            if color.hex != keyColor { keyColor = color.hex }
        case .loadSong(let song):
            load(song)
            if self.song == song { openSongFile = nil }
        case .openPlan(let plan, let songs):
            program = Program(plan: plan, songs: Dictionary(songs.map { ($0.id, $0) }) { first, _ in first }, mode: repetitionMode)
            (programIndex, previewItem) = (-1, nil)
            syncLiveIndex()
        case .previewItem(let item):
            guard let item, item != liveItem else { if previewItem != nil { previewItem = nil }; return }
            if !program.range(of: item).isEmpty, item != previewItem { previewItem = item }
        case .addToService(let url, let position):
            do { add(try Song.decode(from: Data(contentsOf: url)), position) } catch {
                alert = AppAlert(title: Strings.text("The song could not be opened."), message: Strings.text("This file could not be read."))
            }
        case .moveArrangementItem(let from, let to):
            editOrder { order in
                guard order.indices.contains(from), order.indices.contains(to), from != to else { return nil }
                order.insert(order.remove(at: from), at: to)
                return to
            }
        case .insertArrangementItem(let id, let index):
            editOrder { order in
                guard (0...order.count).contains(index), song.sections.contains(where: { $0.id == id }) else { return nil }
                order.insert((id, nil), at: index)
                return index
            }
        case .removeArrangementItem(let index):
            editOrder { order in
                guard order.indices.contains(index), order.count > 1 else { return nil }
                order.remove(at: index)
                return min(index, order.count - 1)
            }
        case .addSection(let kind, let index): addSection(kind, at: index)
        case .setRepetitionMode(let mode): setRepetitionMode(mode)
        case .chooseLibraryFolder(let folder):
            library("The library folder could not be opened.") {
                _ = try Library.open(folder)
                settings?.libraryFolder = folder
                libraryFolder = folder
                openLibraryIndex()
            }
        case .saveSong:
            library("The song could not be saved.") {
                guard let index else { openSongFile = try Library.open(libraryFolder).save(song); return openLibraryIndex() }
                openSongFile = try index.save(song)
                showLibrary(problems: true)
            }
        case .openMostRecentSong:
            guard Library.exists(at: libraryFolder) else { return }
            library("The library folder could not be opened.") { try Library.open(libraryFolder).songs().mostRecent.map { open($0.song, from: $0.url) } }
        case .openLibraryIndex: openLibraryIndex()
        case .setLibrarySearch(let text):
            librarySearch = text
            showLibrary()
        case .openLibrarySong(let url):
            do { open(try Song.decode(from: Data(contentsOf: url)), from: url) } catch {
                alert = AppAlert(title: Strings.text("The song could not be opened."), message: Strings.text("This file could not be read."))
            }
        case .setBackground(let background): setBackground(background)
        case .clearBackground: setBackground(.none)
        }
    }

    /// Adds a song item to the plan after the live item (first when nothing is on air) or at the end, keeping the live slide and the preview.
    private func add(_ song: Song, _ position: ServicePosition) {
        var plan = program.plan
        let index = position == .end ? plan.items.count : liveItem.map { $0 + 1 } ?? 0
        plan.items.insert(PlanItem(id: UUID().uuidString.lowercased(), kind: .song, title: song.title, song: song.id), at: index)
        if let preview = previewItem, preview >= index { previewItem = preview + 1 }
        rebuildProgram(plan: plan, songs: program.songs.merging([song.id: song]) { old, _ in old })
    }

    /// Rebuilds the program keeping the live slide on its item: on `liveIndex` when the item shows the prepared slides, else at its place, clamped.
    private func rebuildProgram(plan: Plan? = nil, songs: [UUID: Song]? = nil) {
        let item = liveItem, offset = item.map { programIndex - program.range(of: $0).lowerBound } ?? 0
        program = Program(plan: plan ?? program.plan, songs: songs ?? program.songs, mode: repetitionMode)
        if let item {
            let range = program.range(of: item)
            let prepared = liveIndex >= 0 && program.slides[range].map(\.slide) == slides
            let index = range.isEmpty ? min(programIndex, program.slides.count - 1) : range.lowerBound + min(prepared ? liveIndex : offset, range.count - 1)
            if index != programIndex { programIndex = index }
        }
        syncLiveIndex()
    }

    /// Puts the edited prepared song into the program when the plan holds it.
    private func preparedSongChanged() {
        if program.songs[song.id] != nil { rebuildProgram(songs: program.songs.merging([song.id: song]) { $1 }) }
    }

    /// Points `liveIndex` at the live slide within the prepared song when the live item shows exactly its slides, else -1.
    private func syncLiveIndex() {
        let range = liveItem.map { program.range(of: $0) } ?? 0..<0
        let index = !range.isEmpty && program.slides[range].map(\.slide) == slides ? programIndex - range.lowerBound : -1
        if index != liveIndex { liveIndex = index }
    }

    /// Validates a background and decodes its image before publishing it; invalid ones and the current one are ignored.
    /// A video is opened here and published once its player is ready; choosing another background first cancels it.
    private func setBackground(_ new: Background) {
        var new = new, image: CGImage?
        switch new {
        case .none: break
        case .color(let hex):
            guard let color = KeyColor(hex: hex) else { return }
            new = .color(color.hex)
        case .image(let url):
            guard new != background, let decoded = BackgroundImageLoader.image(at: url) else { return }
            image = decoded
        case .video(let url):
            guard new != background else { return cancelPendingVideo() }
            guard pendingVideo?.url != url, let video = BackgroundVideo(url: url) else { return }
            cancelPendingVideo()
            pendingVideo = video
            video.prepare { [weak self, weak video] ready in
                guard let self, let video, self.pendingVideo === video else { return }
                self.pendingVideo = nil
                if ready { self.show(.video(url), image: nil, video: video) } else { video.stop() }
            }
            return
        }
        cancelPendingVideo()
        guard new != background else { return }
        show(new, image: image, video: nil)
    }

    private func cancelPendingVideo() {
        pendingVideo?.stop()
        pendingVideo = nil
    }

    /// Publishes a prepared background, stopping the video it replaces and starting its own.
    private func show(_ new: Background, image: CGImage?, video: BackgroundVideo?) {
        backgroundVideo?.stop()
        (backgroundImage, backgroundVideo) = (image, video)
        video?.start()
        background = new
    }

    /// Opens and reconciles the index off the main thread, then shows it on the main thread; until then the list is empty.
    private func openLibraryIndex() {
        libraryLoads += 1
        let load = libraryLoads, folder = libraryFolder
        (index, invalidFiles) = (nil, [])
        showLibrary(problems: true)
        guard let indexURL, Library.exists(at: folder) else { return isLibraryLoading = false }
        isLibraryLoading = true
        indexQueue.async {
            let opened = Result { () throws -> (LibraryIndex, ReconcileReport) in
                let library = try Library.open(folder)
                let index = try LibraryIndex(library: library, at: indexURL(library))
                return (index, try index.reconcile())
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, load == self.libraryLoads else { return }
                self.isLibraryLoading = false
                self.library("The library folder could not be opened.") {
                    let (index, report) = try opened.get()
                    let reason = Strings.text("This file is not a valid song file.")
                    self.invalidFiles = report.problems.map { LibraryProblem(file: $0.url.lastPathComponent, reason: reason) }.sorted { $0.file < $1.file }
                    self.index = index
                }
                self.showLibrary(problems: true)
            }
        }
    }

    /// Lists the songs that match the search and, when asked, the problems; a failing index is reported.
    private func showLibrary(problems: Bool = false) {
        library("The library folder could not be opened.") {
            guard let index else { (librarySongs, libraryProblems) = ([], invalidFiles); return }
            let searching = librarySearch.contains { $0.isLetter || $0.isNumber }
            librarySongs = try searching ? index.search(librarySearch, limit: 10_000) : index.allSongs()
            guard problems else { return }
            let reason = Strings.text("Another file has the same song ID.")
            libraryProblems = try invalidFiles + index.filesWithDuplicateIDs().map { LibraryProblem(file: $0.lastPathComponent, reason: reason) }
        }
    }

    /// Runs a library operation; a failure becomes an alert with the localized title.
    private func library(_ title: String, _ operation: () throws -> Void) {
        do { try operation() } catch { alert = AppAlert(title: Strings.text(title), message: Strings.libraryMessage(for: error)) }
    }

    /// Replaces the primary-language words of a section, keeping each line's other fields, and rebuilds the slides.
    private func setLines(_ sectionID: String, _ lines: [String]) {
        let texts = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !texts.isEmpty, let index = song.sections.firstIndex(where: { $0.id == sectionID }) else { return }
        let old = song.sections[index].lines
        guard texts != old.map({ $0.text[song.language] ?? "" }) else { return }
        var edited = song
        edited.sections[index].lines = texts.enumerated().map { offset, text in
            var line = old.indices.contains(offset) ? old[offset] : SongLine(text: [:])
            line.text[song.language] = text
            return line
        }
        song = edited
        parts = SongPart.parts(of: song, mode: repetitionMode)
        slides = parts.flatMap(\.slides)
        if liveIndex >= slides.count { liveIndex = slides.count - 1 }
        preparedSongChanged()
    }

    /// Changes the order of the default arrangement, creating one when the song has none; `edit` returns the part to select, or nil to ignore the command.
    /// Each entry keeps the index of the part it was, so the live slide stays on the same part; a section that leaves every order and has no words leaves the song.
    private func editOrder(adding section: SongSection? = nil, _ edit: (inout [(id: String, part: Int?)]) -> Int?) {
        var order: [(id: String, part: Int?)] = parts.enumerated().map { ($0.element.section.id, $0.offset) }
        guard let selected = edit(&order) else { return }
        var edited = song, arrangements = song.arrangements ?? []
        if let section { edited.sections.append(section) }
        if let index = arrangements.firstIndex(where: { $0.id == song.defaultArrangement }) {
            arrangements[index].sequence = order.map(\.id)
        } else {
            let id = (0...).lazy.map { $0 == 0 ? "default" : "default\($0 + 1)" }.first { id in !arrangements.contains { $0.id == id } }!
            arrangements.append(SongArrangement(id: id, name: "Default", sequence: order.map(\.id)))
            edited.defaultArrangement = id
        }
        edited.arrangements = arrangements
        let unused = Set(parts.map(\.section.id)).subtracting(arrangements.flatMap(\.sequence))
        edited.sections.removeAll { unused.contains($0.id) && !hasWords($0) }
        let newParts = SongPart.parts(of: edited, mode: repetitionMode), newSlides = newParts.flatMap(\.slides)
        guard !newSlides.isEmpty else { return }
        let live = order.firstIndex { $0.part == livePart }.map { newParts[$0].firstSlide + liveIndex - parts[livePart].firstSlide }
        (song, parts, slides) = (edited, newParts, newSlides)
        let index = min(live ?? liveIndex, slides.count - 1)
        if index != liveIndex { liveIndex = index }
        if selected != selectedPart { selectedPart = selected }
        preparedSongChanged()
    }

    /// Whether a section has words other than the placeholder a new section starts with.
    private func hasWords(_ section: SongSection) -> Bool {
        section.lines.contains { line in
            let text = (line.text[song.language] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !text.isEmpty && text != Strings.newSectionText(section)
        }
    }

    /// Adds a section of a kind with the next free number and id, one placeholder line, and inserts it in the order.
    private func addSection(_ kind: SongSectionKind, at index: Int) {
        let numbers = song.sections.filter { $0.kind == kind }.map { $0.number ?? 1 }
        let number = numbers.max().map { $0 + 1 } ?? (kind == .verse ? 1 : nil)
        let prefix = kind == .prechorus ? "p" : String(kind.rawValue.prefix(1))
        let id = ((number ?? 1)...).lazy.map { "\(prefix)\($0)" }.first { id in !song.sections.contains { $0.id == id } }!
        var section = SongSection(id: id, kind: kind, number: number, lines: [])
        section.lines = [SongLine(text: [song.language: Strings.newSectionText(section)])]
        editOrder(adding: section) { order in
            guard (0...order.count).contains(index) else { return nil }
            order.insert((id, nil), at: index)
            return index
        }
    }

    /// Rebuilds the parts for a repetition mode; the live slide keeps its place in its part, or in the run's first part when its part has no slides.
    private func setRepetitionMode(_ mode: RepetitionMode) {
        settings?.repetitionMode = mode
        guard mode != repetitionMode else { return }
        let newParts = SongPart.parts(of: song, mode: mode), live = max(livePart, 0), offset = liveIndex - parts[live].firstSlide
        let part = newParts[...live].lastIndex { !$0.slides.isEmpty } ?? 0
        let index = liveIndex < 0 ? -1 : newParts[part].firstSlide + min(offset, max(newParts[part].slides.count - 1, 0))
        (repetitionMode, parts, slides) = (mode, newParts, newParts.flatMap(\.slides))
        if index != liveIndex { liveIndex = index }
        rebuildProgram()
    }

    private func open(_ song: Song, from file: URL) {
        load(song)
        if self.song == song { openSongFile = file }
    }

    private func load(_ song: Song) {
        let parts = SongPart.parts(of: song, mode: repetitionMode), slides = parts.flatMap(\.slides)
        guard !slides.isEmpty else { return }
        (self.song, self.parts, self.slides) = (song, parts, slides)
        if selectedPart != 0 { selectedPart = 0 }
        syncLiveIndex()
    }

    private func goToSlide(_ index: Int) {
        guard program.slides.indices.contains(index) else { return }
        if index != programIndex { programIndex = index }
        if previewItem != nil { previewItem = nil }
        if isCleared { isCleared = false }
        syncLiveIndex()
    }
}
