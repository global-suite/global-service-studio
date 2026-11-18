# 0011. Text slides, layouts and editing imported decks

- Status: Accepted
- Date: 2026-11-18

## Context

The slide editor lets a first-time volunteer create simple slides in the app: a new slide starts from a layout (Title, Title + Text, Text only, Image + Caption, Image full) and the text is typed straight onto it. The editor saves automatically, with undo. Imported Keynote, PowerPoint and PDF decks ([ADR 0010](0010-importing-keynote-powerpoint-and-pdf.md)) open in the same editor: their slides can be reordered, hidden or deleted and their notes edited, "Fix in Keynote" opens the original, and "Update from Keynote" imports it again.

The formats ([ADR 0005](0005-file-format-design.md)) do not cover all of this yet:

- A theme defines only the `lyrics`, `translation` and `footer` slots (`Sources/GSSCore/Theme/Theme.swift:7`), while layouts need a title, a body and a caption.
- A slide has an `id`, a `label`, `elements` and `notes` (`Sources/GSSCore/Presentation/PresentationParts.swift:4-9`), but no layout and no way to be hidden.
- An imported deck is an ordinary presentation of full-frame images (`Sources/GSSLibrary/LibraryPresentations.swift:96-105`) and keeps no link to the file it came from, so it cannot be updated from it.

Saved formats are a contract ([ADR 0004](0004-open-file-formats.md)), so these additions are decided first.

## Decision

Every addition is an optional field and every new value is an open string value. Under the shared rules of [ADR 0005](0005-file-format-design.md) (rules 3 and 4) the theme and presentation formats stay at version 1 and no migration is needed. An older reader keeps the new fields as unknown fields and writes them back unchanged; an absent field stays absent when the file is written.

### Theme slots `title`, `body` and `caption`

A theme may define three more slots, with the same shape as the existing ones (`Sources/GSSCore/Theme/ThemeParts.swift:36-48`): `title`, `body` and `caption`. When a theme lacks one, the app uses a default derived from the theme's `lyrics` slot, so every existing theme works with every layout:

| Slot | Default when the theme lacks it |
|---|---|
| `body` | A copy of the `lyrics` slot, with `y` 0.3 and `height` 0.6 so it sits under the title. |
| `title` | The `lyrics` font family, color and alignment; weight `bold`; size 1.4 times the `lyrics` size; frame with the `lyrics` `x` and `width`, `y` 0.08 and `height` 0.18. |
| `caption` | The `lyrics` font family, weight, color and alignment; size 0.6 times the `lyrics` size; frame with the `lyrics` `x` and `width`, `y` 0.82 and `height` 0.1; `maxLines` 2. |

A theme without a `lyrics` slot uses the app's built-in theme as the source of these defaults. The defaults are computed when the theme is read and never written into the theme file.

### Slide `layout`

A slide gains an optional `layout`, an open value. Each layout says which slots and pictures its slide has:

| Value | Shown in the gallery as | Slide contents |
|---|---|---|
| `title` | Title | Text in `title`, and a short line in `body` |
| `titleText` | Title + Text | Text in `title` and in `body` |
| `text` | Text only | Text in `body` |
| `imageCaption` | Image + Caption | An `image` element with the `lyrics` `x` and `width`, `y` 0.08 and `height` 0.7, and text in `caption` |
| `image` | Image full | One `image` element with the full-canvas frame, scaled to `fit` |

- The layout's text is stored as ordinary `text` elements whose `slot` names the slot; images are ordinary `image` elements with their own `frame`. The layout only guides the editor; a renderer draws the slide from its elements alone, so an absent or unknown layout still renders.
- Changing a layout keeps the text. Each text element keeps its slot when the new layout has it; any other text moves to `body`, joined to the text already there, so nothing typed is lost. An image is kept when the new layout has a picture and removed otherwise; undo brings it back.
- The editor creates text only in this version: no shapes and no free placement. A slide without a `layout`, such as an imported slide, is edited as it is.

### Slide `hidden`

A slide gains an optional `hidden` flag, written only when it is `true`. A hidden slide is left out of the program, so it never goes on air and Next goes past it; the editor shows it dimmed. It works the same for imported and created slides.

### Presentation `source`

An imported deck gains an optional `source` that records the file it came from:

```json
"source": {
  "kind": "keynote",
  "path": "/Users/…/Missions Update.key",
  "bookmark": "Ym9va21hcmsgZGF0YQ…",
  "importedAt": "2026-11-18T14:30:00Z"
}
```

- `kind` is an open value: `keynote`, `powerPoint` or `pdf`.
- `path` is the last known absolute path of the file. Unlike references inside the library (ADR 0005, rule 6), the source lives outside it, so a path is the only portable hint.
- `bookmark` is optional security-scoped bookmark data, in Base64, written when macOS provides it. It finds the file after it is moved or renamed. `GSSCore` stores it as text; only the app resolves it.
- `importedAt` is the time of the last import, in UTC, in RFC 3339 form.

"Fix in Keynote" resolves the bookmark, then the path, and opens the file in its application; the label names that application. When neither finds the file, the app asks the operator to locate it and records the new path and bookmark.

"Update from Keynote" imports the file again through the pipeline of ADR 0010:

- Slides are matched by position. The importer names the slide at position *n* `s`*n* (`Sources/GSSLibrary/LibraryPresentations.swift:102`), so that `id` records its original position even after the operator reorders slides. Slides created in the app take other identifiers.
- A matched slide gets the new picture and keeps its place in the app's order, its `hidden` flag, its `notes` and any element added over the picture.
- A slide of the new export with no match (added in Keynote, or deleted in the app) is inserted after the slide matched to the position before it. A slide whose position no longer exists is removed.
- The operator sees a report of what could not be kept: removed slides and the notes or text boxes they carried, slides added back, and slides whose notes in Keynote now differ from the notes kept in the app.

### A text box over an imported picture

From the editor version on, the operator may add a text element to an imported slide, for example to correct a typo in the picture. It is an ordinary `text` element with its own `frame` or a slot, listed after the picture so it is drawn on top. The picture itself stays uneditable, as ADR 0010 decided; this extends that decision without replacing it.

### Autosave and undo

Saving is app behavior and changes no format. After each change the file is written, debounced, through the library's atomic save (`Sources/GSSLibrary/LibraryPresentations.swift:26`). Undo and redo work within the session. No history of file versions is kept. A failed save says so and keeps the slides open so the operator can try again.

## Alternatives considered

- **A new format version.** Unneeded: every addition is optional, and older readers keep the fields they do not know.
- **A free-form canvas without layouts.** It offers more freedom, but it is harder for a first-time volunteer, who must place and size every box. The owner chose layouts.
- **Storing a copy of the source file in the library.** It would always be found, but decks with media are large and the library is synced. A reference is enough, and the app asks for the file when it is missing.
- **Converting PowerPoint slides into editable slides.** Left for later, in a separate ADR.

## Consequences

- Existing themes work with every layout through the defaults. The theme editor must later offer the `title`, `body` and `caption` slots so a theme can style them.
- Bookmarks and paths go stale when a file is moved, renamed or opened on another Mac. The app then asks the operator to locate the file.
- Hidden slides change what Next does and what the operator sees in Live. An older version shows hidden slides, and may not place text in a slot its theme lacks; it still keeps the fields.
- Matching by position is simple but blind to slides moved inside Keynote: a moved slide keeps the notes of the slide that was at its position before. The report makes such changes visible.
- Autosave means there is no Save button and no Revert. Undo covers mistakes made in the session; earlier states come from the operator's own backups.
