import AppKit
import GSSCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// What the media layer shows (ADR 0008): nothing, a solid color as `#RRGGBB`, or a still image file.
public enum Background: Equatable, Sendable {
    case none
    case color(String)
    case image(URL)
}

/// What an output draws in its media layer, ready to draw: the image is already decoded.
enum MediaFill: Equatable {
    case color(RGBA)
    case image(CGImage)
}

/// Decodes background images when a command is applied, never on the render path or in a view body.
enum BackgroundImageLoader {
    /// The longest side a background is decoded at; larger images are scaled down, which bounds memory on 4K outputs.
    static let maxPixelSize = 3840

    /// The decoded image of a readable image file; nil for anything else.
    static func image(at url: URL) -> CGImage? {
        guard url.isFileURL, let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetType(source) != nil,
              CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize, kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

extension AppState {
    /// What an output with a role draws in its media layer; nil when the role never shows it, as the key output, or there is no background.
    func mediaFill(for role: OutputRole) -> MediaFill? {
        guard role.shows(.media) else { return nil }
        switch background {
        case .none: return nil
        case .color(let hex): return KeyColor(hex: hex).map { .color($0.rgba) }
        case .image: return backgroundImage.map { .image($0) }
        }
    }
}

/// The media layer: the background color, or the image filling the output (aspect fill); transparent without one.
struct MediaLayer: View {
    let fill: MediaFill?

    var body: some View {
        GeometryReader { geometry in
            switch fill {
            case .color(let color): color.color
            case .image(let image):
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            case nil: Color.clear
            }
        }
    }
}

/// The Background submenu of the Output menu, until the media bin exists: choose an image, a preset color, or clear.
final class BackgroundMenuController: NSObject, NSMenuItemValidation {
    /// The preset colors, by localization key.
    static let presets = [("Black", "#000000"), ("Dark Blue", "#0B1F3A"), ("Dark Gray", "#2B2B2B")]
    let state: AppState
    let menu = NSMenu(title: Strings.text("Background"))
    private let chooseImageFile: () -> URL?

    /// `chooseImageFile` asks for an image file; nil when the operator cancels.
    init(state: AppState, chooseImageFile: @escaping () -> URL? = BackgroundMenuController.openPanel) {
        (self.state, self.chooseImageFile) = (state, chooseImageFile)
        super.init()
        menu.addItem(item("Choose Image…", #selector(chooseImage(_:))))
        menu.addItem(.separator())
        for (index, preset) in Self.presets.enumerated() { menu.addItem(item(preset.0, #selector(choosePreset(_:)), tag: index)) }
        menu.addItem(.separator())
        menu.addItem(item("Clear Background", #selector(clearBackground(_:))))
    }

    private func item(_ title: String, _ action: Selector, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: Strings.text(title), action: action, keyEquivalent: "")
        (item.target, item.tag) = (self, tag)
        return item
    }

    /// An open panel that accepts only images.
    static func openPanel() -> URL? {
        let panel = NSOpenPanel()
        (panel.allowedContentTypes, panel.allowsMultipleSelection, panel.canChooseDirectories) = ([.image], false, false)
        return panel.runModal() == .OK ? panel.url : nil
    }

    @objc func chooseImage(_ sender: Any?) { chooseImageFile().map { state.perform(.setBackground(.image($0))) } }
    @objc func choosePreset(_ sender: NSMenuItem) { state.perform(.setBackground(.color(Self.presets[sender.tag].1))) }
    @objc func clearBackground(_ sender: Any?) { state.perform(.clearBackground) }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(choosePreset(_:)) { menuItem.state = state.background == .color(Self.presets[menuItem.tag].1) ? .on : .off }
        return menuItem.action != #selector(clearBackground(_:)) || state.background != .none
    }
}
