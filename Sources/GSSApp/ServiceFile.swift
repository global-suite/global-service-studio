import AppKit
import GSSLibrary

/// The `YYYY-MM-DD` day of a service in the local time zone, and its display in the interface language.
enum ServiceDate {
    private static let posix: DateFormatter = {
        let formatter = DateFormatter()
        (formatter.calendar, formatter.locale, formatter.dateFormat) = (Calendar(identifier: .gregorian), Locale(identifier: "en_US_POSIX"), "yyyy-MM-dd")
        return formatter
    }()
    static var today: String { string(from: Date()) }
    static func string(from date: Date) -> String { posix.string(from: date) }
    static func date(from text: String) -> Date? { posix.date(from: text) }
    /// The day in the medium date style of the interface language, such as "Nov 15, 2026"; nil without a valid date.
    static func display(_ text: String?, language: String = Strings.language) -> String? {
        text.flatMap(date(from:))?.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: Locale(identifier: language)))
    }
}

/// What to ask before the service is replaced by another or the app quits.
enum ServiceFile {
    enum Question: Equatable { case saveChanges, endAir }

    /// Unsaved changes ask Save, Don't Save or Cancel; something on air asks to confirm, except when quitting.
    static func questions(unsaved: Bool, onAir: Bool, quitting: Bool) -> [Question] {
        (unsaved ? [.saveChanges] : []) + (onAir && !quitting ? [.endAir] : [])
    }
}

/// The New Service from Template submenu, listing the library's templates by title each time it opens.
final class ServiceMenus: NSObject, NSMenuDelegate {
    let state: AppState, templates = NSMenu()

    init(state: AppState) { self.state = state }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let listing = Library.exists(at: state.libraryFolder) ? try? Library.open(state.libraryFolder).plans() : nil
        menu.items = (listing?.templates ?? []).map { stored in
            let item = NSMenuItem(title: stored.plan.title, action: #selector(MainWindowController.newServiceFromTemplate(_:)), keyEquivalent: "")
            item.representedObject = stored.url
            return item
        }
        if menu.items.isEmpty { menu.items = [NSMenuItem(title: Strings.text("None"), action: nil, keyEquivalent: "")] }
    }
}

extension MainWindowController: NSOpenSavePanelDelegate {
    /// Asks the questions `ServiceFile.questions` gives, one alert at a time; false when the operator cancels or saving fails.
    func mayReplaceService(quitting: Bool = false) -> Bool {
        for question in ServiceFile.questions(unsaved: state.hasUnsavedServiceChanges, onAir: state.isOnAir, quitting: quitting) {
            let alert = NSAlert(), save = question == .saveChanges
            alert.messageText = Strings.text(save ? "Do you want to save the changes to this service?" : "This ends what is on air.")
            alert.informativeText = Strings.text(save ? "Your changes are lost if you don't save them." : "The words leave the screens and the background stays.")
            for title in save ? ["Save", "Don't Save", "Cancel"] : ["Continue", "Cancel"] { alert.addButton(withTitle: Strings.text(title)) }
            alert.buttons.last?.keyEquivalent = "\u{1b}"
            let answer = alert.runModal()
            if answer == (save ? .alertThirdButtonReturn : .alertSecondButtonReturn) { return false }
            if save, answer == .alertFirstButtonReturn {
                state.perform(.saveService)
                if state.hasUnsavedServiceChanges { return false }
            }
        }
        return true
    }

    /// File > New Service.
    @objc func newService(_ sender: Any?) { if mayReplaceService() { state.perform(.newService) } }
    /// File > New Service from Template > a template.
    @objc func newServiceFromTemplate(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL, mayReplaceService() { state.perform(.newServiceFromTemplate(url)) }
    }
    /// File > Save Service.
    @objc func saveService(_ sender: Any?) { state.perform(.saveService) }

    /// File > Open Service…: chooses a `.plan.json` file, starting in the library's Plans folder.
    @objc func openService(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        (panel.directoryURL, panel.delegate) = (state.libraryFolder.appendingPathComponent("Plans"), self)
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self, self.mayReplaceService() else { return }
            self.state.perform(.openService(url))
        }
    }

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool { url.hasDirectoryPath || url.lastPathComponent.hasSuffix(".plan.json") }

    /// File > Service Info…: edits the title and date of the service.
    @objc func showServiceInfo(_ sender: Any?) {
        guard let window else { return }
        let alert = NSAlert(), title = NSTextField(string: state.program.plan.title), picker = NSDatePicker()
        (picker.datePickerStyle, picker.datePickerElements, picker.locale) = (.textFieldAndStepper, .yearMonthDay, Locale(identifier: Strings.language))
        picker.dateValue = state.program.plan.date.flatMap(ServiceDate.date(from:)) ?? Date()
        title.widthAnchor.constraint(equalToConstant: 260).isActive = true
        let grid = NSGridView(views: [[NSTextField(labelWithString: Strings.text("Title")), title], [NSTextField(labelWithString: Strings.text("Date")), picker]])
        grid.frame.size = grid.fittingSize
        (alert.messageText, alert.accessoryView) = (Strings.text("Service Info"), grid)
        for button in ["OK", "Cancel"] { alert.addButton(withTitle: Strings.text(button)) }
        alert.buttons[1].keyEquivalent = "\u{1b}"
        alert.window.initialFirstResponder = title
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.state.perform(.setServiceInfo(title: title.stringValue, date: ServiceDate.string(from: picker.dateValue)))
        }
    }
}
