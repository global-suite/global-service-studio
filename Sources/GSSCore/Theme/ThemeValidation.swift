import Foundation

extension Theme {
    /// Checks sizes, frames inside the canvas, colors and media paths.
    public func validate() throws {
        func fail(_ reason: String, _ path: String) -> FormatError { .validation(reason: reason, at: path) }
        func positive(_ value: Double, _ at: String) throws { if !(value > 0) { throw fail("nonPositiveSize", at) } }
        func color(_ value: String, _ path: String) throws {
            let digits = value.dropFirst()
            guard value.first == "#", [6, 8].contains(digits.count),
                  digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { throw fail("invalidColor", path) }
        }
        try positive(canvas.width, "canvas.width")
        try positive(canvas.height, "canvas.height")
        if let value = background.color { try color(value, "background.color") }
        if background.kind == .color, background.color == nil { throw fail("missingColor", "background.color") }
        if background.kind == .image || background.kind == .video {
            guard let media = background.media else { throw fail("missingMedia", "background.media") }
            if !media.hasLibraryRelativePath { throw fail("invalidMediaPath", "background.media.path") }
        }
        let tolerance = 1e-9
        for (name, slot) in slots.sorted(by: { $0.key < $1.key }) {
            let path = "slots.\(name)", frame = slot.frame
            try positive(frame.width, path + ".frame.width")
            try positive(frame.height, path + ".frame.height")
            guard frame.x >= -tolerance, frame.y >= -tolerance, frame.x + frame.width <= 1 + tolerance,
                  frame.y + frame.height <= 1 + tolerance else { throw fail("frameOutsideCanvas", path + ".frame") }
            try positive(slot.font.size, path + ".font.size")
            if let maxLines = slot.maxLines, maxLines < 1 { throw fail("invalidMaxLines", path + ".maxLines") }
            try color(slot.color, path + ".color")
        }
    }
}
