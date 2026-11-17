# 0010. Importing Keynote, PowerPoint and PDF slides

- Status: Accepted
- Date: 2026-11-16

## Context

Churches prepare sermon and announcement slides in Keynote or PowerPoint, and sometimes as PDF. Those slides must reach the screens looking exactly as their authors designed them: the same fonts, layout and images. A volunteer who opens the app for the first time should be able to import a file and show it without learning a slide editor.

Four constraints shape how that is done:

- **No required closed dependency** ([ADR 0006](0006-extensibility-and-live-performance.md)). Keynote and PowerPoint are closed applications that may not be installed.
- **Saved formats are a contract** ([ADR 0004](0004-open-file-formats.md)). Imported slides should fit the existing presentation format ([ADR 0005](0005-file-format-design.md)) without a version bump.
- **Slides and screens differ in proportion.** A 4:3 deck shown on a 16:9 screen, or the reverse, needs a defined behavior.
- **The render path is closed** ([ADR 0006](0006-extensibility-and-live-performance.md)). Importing reads files and talks to other applications, so it must stay away from the output.

## Decision

### Imported slides are images, faithful to the original

Each imported slide becomes one picture of the slide as its author made it. It is not editable in the app: to change something, the author edits the deck in Keynote or PowerPoint and imports it again. Animations, builds and embedded video become the slide's final state. Converting slides into editable text and shapes is left for later, and creating simple slides in the app is a separate feature.

### One pipeline, through PDF

Every source becomes a PDF first, and the app renders that PDF itself.

- **Keynote (`.key`).** The app asks Keynote, through Apple Events, to export the deck as PDF without skipped slides, and reads each slide's presenter notes.
- **PowerPoint (`.pptx`, `.ppt`).** The app opens the file with Keynote and exports it the same way. When only PowerPoint is installed, PowerPoint exports the PDF instead.
- **PDF.** The file is used directly. This path needs no other application, so PDF import works on any Mac.
- **Rendering.** The app opens the PDF with `CGPDFDocument` and draws each page into a bitmap with `CGContext.drawPDFPage(_:)` at the output size: 1920 × 1080, or 3840 × 2160 for a 4K output. Because the PDF is resolution independent, the same deck can be rendered again at another size.
- **When an application is missing**, the app says which one it needs, for example "Keynote is needed to import Keynote files", and suggests exporting the deck as PDF from the application that made it. It never fails silently.

### Storage uses the existing presentation format

An imported deck is an ordinary `gss.presentation` file in the library's `Presentations/` folder, version 1:

- Each slide becomes one `PresentationSlide` with a single `image` element. Its `frame` covers the whole canvas (`x` 0, `y` 0, `width` 1, `height` 1), which the format's validation already accepts (`Sources/GSSCore/Presentation/PresentationValidation.swift:20-31`).
- The rendered image is stored in the library's `Media/` folder and referenced with a `MediaReference`: a library-relative path plus its `sha256` (`Sources/GSSCore/Format/SharedValues.swift:13-30`). Identical images are stored once.
- Speaker notes go in the slide's existing `notes` field (`Sources/GSSCore/Presentation/PresentationParts.swift:8`). A PDF has no notes.
- Hidden (skipped) slides are not imported.

```json
{
  "id": "s1",
  "elements": [
    {
      "id": "e1",
      "kind": "image",
      "frame": { "x": 0, "y": 0, "width": 1, "height": 1 },
      "media": { "path": "Media/…", "sha256": "…" },
      "scaling": "fit"
    }
  ],
  "notes": "Invented reminder for the speaker"
}
```

### Scaling: a new optional field on image elements

An image element gains an optional `scaling` field that decides how the image fills its frame when their proportions differ:

| Value | Behavior |
|---|---|
| `fit` (default) | The whole image shows, uncut and undistorted. The bands left over are transparent, so the media layer behind the slide shows through. |
| `fill` | The image covers the whole frame without distortion, and the overflow is cropped. |
| `stretch` | The image covers the whole frame and is distorted to match it. |

- An absent field means `fit`. The importer writes the field on every slide it creates, and the operator changes it for a whole presentation at once, which rewrites it on every slide.
- The field follows the shared rules for an optional field ([ADR 0005](0005-file-format-design.md), rules 3 and 4): the format version stays 1 and no migration is needed. An older reader keeps the field as an unknown field and writes it back unchanged.
- The value is an open string value. A value the app does not know is preserved as written and displayed as `fit`.

For comparison, ProPresenter offers Scale to Fit, Scale to Fill and Stretch to Fill, plus a Scale + Blur mode, and uses Scale to Fit with black bars by default for foreground media. Transparent bands are chosen instead of black so the background stays visible.

### Permissions

- Sending Apple Events to Keynote or PowerPoint needs the user's consent. macOS asks the first time the app controls each application; the import explains why before that prompt appears, and explains how to allow it in System Settings if it was denied.
- A bundled app declares `NSAppleEventsUsageDescription` in its `Info.plist`, and the text is localized in English and Spanish like every other user-facing string.
- A signed app with the hardened runtime needs the `com.apple.security.automation.apple-events` entitlement.
- In development the app runs unbundled from Terminal, and macOS may attribute the permission to Terminal instead of the app. The import is checked in a bundled build before it ships.
- Importing a PDF needs no permission.

### Off the main thread, never on the render path

Exporting, rendering pages, hashing and writing files run in the background, with progress and cancellation shown in the interface. The render engine only ever sees finished images that are already in the library, prepared before the presentation goes live like any other media ([ADR 0008](0008-media-layer-key-output-and-video.md)).

## Alternatives considered

- **Exporting slide images straight from Keynote.** Keynote can export one image per slide, but its scripting options offer no control over the image size, so 4K output could not be guaranteed. Exporting PDF and rendering it in the app gives that control.
- **LibreOffice as the converter.** It is open, but it is a large dependency to bundle or require, it cannot open Keynote files, and it renders PowerPoint with lower fidelity than Keynote or PowerPoint themselves.
- **Quick Look thumbnails.** No extra application is needed, but they provide one image per file, not one per slide.
- **Converting slides into editable text and shapes.** It is what users would like eventually, but it is costly to build and never exact: fonts, effects and layouts drift. It stays a later option on top of this pipeline.

## Consequences

- Imported slides look like the original, because Keynote or PowerPoint draws them and the app only renders the resulting PDF.
- Importing `.key` files needs Keynote, which may not be installed. PDF import works everywhere, so there is always a way in.
- How faithfully Keynote renders PowerPoint files is not verified yet. It is checked with real decks before PowerPoint import ships, and PowerPoint's own export is preferred if it proves better.
- The first Keynote or PowerPoint import shows a macOS permission prompt, which a first-time volunteer must accept. The app explains it beforehand.
- An imported slide cannot be edited in the app. Changing it means re-importing the deck, which replaces its images.
- Rendering many 4K pages takes time and disk space. The import time on the Intel test machine ([ADR 0002](0002-minimum-macos-13.md)) is measured when the feature is built.
- `scaling` is an additive field: files that use it still open in older versions, which keep it and ignore it.
