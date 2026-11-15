import Foundation

extension Theme {
    /// Checks sizes, frames inside the canvas, colors and media paths.
    public func validate() throws {
        func fail(_ reason: String, _ path: String) -> FormatError { .validation(reason: reason, at: path) }
        func positive(_ value: Double, _ at: String) throws { if !(value > 0) { throw fail("nonPositiveSize", at) } }
        try positive(canvas.width, "canvas.width")
        try positive(canvas.height, "canvas.height")
        try background.validate(at: "background")
        let tolerance = 1e-9
        for (name, slot) in slots.sorted(by: { $0.key < $1.key }) {
            let path = "slots.\(name)", frame = slot.frame
            try positive(frame.width, path + ".frame.width")
            try positive(frame.height, path + ".frame.height")
            guard frame.x >= -tolerance, frame.y >= -tolerance, frame.x + frame.width <= 1 + tolerance,
                  frame.y + frame.height <= 1 + tolerance else { throw fail("frameOutsideCanvas", path + ".frame") }
            try positive(slot.font.size, path + ".font.size")
            if let maxLines = slot.maxLines, maxLines < 1 { throw fail("invalidMaxLines", path + ".maxLines") }
            try validateColor(slot.color, at: path + ".color")
        }
    }
}

extension ThemeBackground {
    /// Checks the color and media of a background found at `path`; unknown kinds pass.
    /// Themes and songs share these rules, so their error reasons match.
    func validate(at path: String) throws {
        if let color { try validateColor(color, at: path + ".color") }
        if kind == .color, color == nil { throw FormatError.validation(reason: "missingColor", at: path + ".color") }
        if kind == .image || kind == .video {
            guard let media else { throw FormatError.validation(reason: "missingMedia", at: path + ".media") }
            if !media.hasLibraryRelativePath {
                throw FormatError.validation(reason: "invalidMediaPath", at: path + ".media.path")
            }
        }
    }
}

/// Checks that `value` is `#RRGGBB` or `#RRGGBBAA`.
func validateColor(_ value: String, at path: String) throws {
    let digits = value.dropFirst()
    guard value.first == "#", [6, 8].contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
        throw FormatError.validation(reason: "invalidColor", at: path)
    }
}
