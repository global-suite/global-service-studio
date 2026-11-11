import Foundation

extension Presentation {
    /// Checks unique ids, what each element kind needs, frames inside the canvas, sizes and colors.
    public func validate() throws {
        func fail(_ reason: String, _ path: String) -> FormatError { .validation(reason: reason, at: path) }
        func positive(_ value: Double, _ at: String) throws { if !(value > 0) { throw fail("nonPositiveSize", at) } }
        let tolerance = 1e-9
        var slideIds = Set<String>()
        for (s, slide) in slides.enumerated() {
            guard slideIds.insert(slide.id).inserted else { throw fail("duplicateSlideId", "slides[\(s)].id") }
            var elementIds = Set<String>()
            for (e, element) in slide.elements.enumerated() {
                let path = "slides[\(s)].elements[\(e)]"
                guard elementIds.insert(element.id).inserted else { throw fail("duplicateElementId", path + ".id") }
                if element.kind == .text {
                    if element.text?.isEmpty ?? true { throw fail("missingText", path + ".text") }
                    if element.slot == nil, element.frame == nil { throw fail("missingSlotOrFrame", path) }
                }
                if element.kind == .image || element.kind == .video {
                    if element.frame == nil { throw fail("missingFrame", path + ".frame") }
                    guard let media = element.media else { throw fail("missingMedia", path + ".media") }
                    if !media.hasLibraryRelativePath { throw fail("invalidMediaPath", path + ".media.path") }
                }
                if let frame = element.frame {
                    try positive(frame.width, path + ".frame.width")
                    try positive(frame.height, path + ".frame.height")
                    let inside = frame.x >= -tolerance && frame.y >= -tolerance
                        && frame.x + frame.width <= 1 + tolerance && frame.y + frame.height <= 1 + tolerance
                    if !inside { throw fail("frameOutsideCanvas", path + ".frame") }
                }
                if let font = element.font { try positive(font.size, path + ".font.size") }
                if let color = element.color, !(color.first == "#" && [7, 9].contains(color.count)
                    && color.dropFirst().allSatisfy({ $0.isASCII && $0.isHexDigit })) {
                    throw fail("invalidColor", path + ".color")
                }
            }
        }
    }
}
