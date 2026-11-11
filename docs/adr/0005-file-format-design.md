# 0005. Design of the song, theme, presentation and service plan formats

- Status: Accepted
- Date: 2026-11-11

## Context

[ADR 0004](0004-open-file-formats.md) decided that user content lives in open, versioned JSON files. This record designs those files.

The design comes from studying how planning and presentation software model the same content. The recurring problems:

- **Slide breaks are stored in the lyrics.** A song split for the main screen has to be split again by hand for a two-line broadcast overlay.
- **Styling is embedded in every slide.** Changing the look means editing every presentation.
- **Two languages mean duplicated text**, kept in step by hand or with separate tools.
- **A song has one order**, or arrangements are matched by section name, so "Chorus" and "Chorus 1" fail to match.
- **Planning tools and presentation tools use different models.** A plan knows headers, lengths and notes but not slides; a presentation tool knows slides but not the plan.
- **Formats are undocumented**, so a library cannot leave the application that created it.

## Decision

### Rules shared by every file

1. **One item per file.** The file name ends in `.song.json`, `.theme.json`, `.presentation.json` or `.plan.json`.
2. **Every file starts with the same envelope:** `format` (for example `gss.song`), `version` (an integer) and `id` (a UUID that never changes, even if the file is renamed or moved).
3. **Unknown fields are preserved.** An application that reads a field it does not understand writes it back unchanged.
4. **Adding an optional field does not change `version`.** The version changes only when an older reader would misread the file. A reader refuses a version newer than it supports instead of guessing.
5. **Output is deterministic:** UTF-8, sorted keys, two-space indentation, a final newline. Saving an unchanged item produces identical bytes, so file-sync tools and Git see real changes only.
6. **References use identifiers, never names or paths.** Media is referenced by a library-relative path plus a content hash.
7. **`externalIds` maps an item to other systems**, namespaced by system: `{"planningCenter": {"songId": "123"}}`.
8. **`extensions` holds data owned by other tools**, namespaced the same way. The application never interprets it.
9. **Language tags follow BCP 47** (`en`, `es`, `pt-BR`).

### Song

A song stores **what is sung**, not how it looks or where slides break.

```json
{
  "format": "gss.song",
  "version": 1,
  "id": "6f1c2b9e-0d0a-4a37-9b1e-2f6d1c3a7e10",
  "title": "Morning Light",
  "titles": { "es": "Luz de la mañana" },
  "language": "en",
  "authors": [{ "name": "A. Writer", "role": "words" }],
  "copyright": "Public Domain",
  "ccliNumber": null,
  "key": "G",
  "tempo": 72,
  "timeSignature": "4/4",
  "tags": ["hymn"],
  "sections": [
    {
      "id": "v1",
      "kind": "verse",
      "number": 1,
      "lines": [
        {
          "text": { "en": "Morning light is rising", "es": "La luz del día nace" },
          "chords": [{ "at": 0, "chord": "G" }, { "at": 17, "chord": "C" }]
        },
        {
          "text": { "en": "Over all the earth", "es": "Sobre la tierra" },
          "breakAfter": "slide"
        }
      ]
    },
    {
      "id": "c1",
      "kind": "chorus",
      "lines": [{ "text": { "en": "We lift our voice", "es": "Alzamos nuestra voz" } }]
    }
  ],
  "arrangements": [
    { "id": "default", "name": "Default", "sequence": ["v1", "c1", "v1", "c1"] },
    { "id": "short", "name": "Short", "sequence": ["v1", "c1"] }
  ],
  "defaultArrangement": "default",
  "externalIds": {},
  "extensions": {}
}
```

- **Sections** have an `id` unique within the song, a `kind` (`verse`, `chorus`, `prechorus`, `bridge`, `intro`, `outro`, `tag`, `interlude`, `ending`, `other`), an optional `number` and an optional custom `label`. Display names such as "Verse 1" are produced from `kind` and `number` in the interface language.
- **Lines** hold `text` per language. The song's `language` is the primary one and must be present on every line; other languages may be missing.
- **Slides are not stored.** The renderer groups lines into slides using the theme's limits. `breakAfter: "slide"` on a line forces a break there for operators who want full control.
- **Chords** belong to the primary-language text. `at` is an offset counted in Unicode code points. They are stored now and displayed later.
- **Arrangements** are named sequences of section identifiers. Editing a chorus once changes every place it is sung.

### Theme

A theme stores **how content looks**, with no content in it.

```json
{
  "format": "gss.theme",
  "version": 1,
  "id": "b2a4c8d0-5e2f-4c61-8a55-90f1e7d3c421",
  "name": "Clean Dark",
  "canvas": { "width": 1920, "height": 1080 },
  "background": { "kind": "color", "color": "#000000" },
  "slots": {
    "lyrics": {
      "frame": { "x": 0.08, "y": 0.2, "width": 0.84, "height": 0.6 },
      "font": { "family": "Helvetica Neue", "weight": "bold", "size": 0.075 },
      "color": "#FFFFFF",
      "align": "center",
      "maxLines": 4,
      "wrap": "balanced"
    },
    "translation": {
      "frame": { "x": 0.08, "y": 0.62, "width": 0.84, "height": 0.25 },
      "font": { "family": "Helvetica Neue", "weight": "regular", "size": 0.05 },
      "color": "#CFCFCF",
      "align": "center",
      "maxLines": 4,
      "wrap": "balanced"
    },
    "footer": {
      "frame": { "x": 0.08, "y": 0.92, "width": 0.84, "height": 0.05 },
      "font": { "family": "Helvetica Neue", "weight": "regular", "size": 0.02 },
      "color": "#8A8A8A",
      "align": "center"
    }
  },
  "languages": { "layout": "stacked" }
}
```

- Sizes and positions are fractions of the canvas, so one theme works at any resolution.
- `maxLines` and `wrap` are what replace stored slide breaks. A lower-third theme sets `maxLines: 2`; the same song needs no editing.
- `languages.layout` decides how a second language appears: `primaryOnly`, `stacked` or `alternating`.

### Presentation

A presentation is free-form: announcements, a sermon outline, a title card. Here slides **are** stored, because the author designs each one.

```json
{
  "format": "gss.presentation",
  "version": 1,
  "id": "0a9d3f77-41c2-4b0e-9d6a-3c5f2e8b7a19",
  "title": "Welcome",
  "theme": "b2a4c8d0-5e2f-4c61-8a55-90f1e7d3c421",
  "slides": [
    {
      "id": "s1",
      "label": "Welcome",
      "elements": [
        {
          "id": "e1",
          "kind": "text",
          "slot": "lyrics",
          "text": { "en": "Welcome", "es": "Bienvenidos" }
        },
        {
          "id": "e2",
          "kind": "image",
          "frame": { "x": 0.4, "y": 0.05, "width": 0.2, "height": 0.12 },
          "media": { "path": "Media/logo.png", "sha256": "…" }
        }
      ]
    }
  ]
}
```

A text element either fills a theme `slot` and takes its style, or declares its own `frame` and style. Text is per language, like song lines.

### Service plan

A plan is the order of service. It holds what a planning tool holds, plus what the screen needs.

```json
{
  "format": "gss.plan",
  "version": 1,
  "id": "d51b0c3e-7a42-4f0b-b6f1-18a2c9e4d702",
  "title": "Sunday Service",
  "date": "2026-11-15",
  "times": [{ "name": "Morning", "start": "10:00" }],
  "theme": "b2a4c8d0-5e2f-4c61-8a55-90f1e7d3c421",
  "items": [
    { "id": "i1", "kind": "header", "title": "Worship" },
    {
      "id": "i2",
      "kind": "song",
      "song": "6f1c2b9e-0d0a-4a37-9b1e-2f6d1c3a7e10",
      "arrangement": "short",
      "sequence": ["v1", "c1", "c1"],
      "key": "A",
      "length": 240,
      "position": "during",
      "notes": [{ "category": "Vocals", "text": "Repeat the chorus softly" }]
    },
    {
      "id": "i3",
      "kind": "presentation",
      "presentation": "0a9d3f77-41c2-4b0e-9d6a-3c5f2e8b7a19",
      "length": 120
    },
    { "id": "i4", "kind": "media", "title": "Countdown", "media": { "path": "Media/countdown.mp4", "sha256": "…" } },
    { "id": "i5", "kind": "item", "title": "Sermon", "length": 1800 }
  ],
  "externalIds": {},
  "extensions": {}
}
```

- Item kinds are `header`, `song`, `presentation`, `media` and `item` (anything with a title and a length but nothing to show).
- A song item points to a song and an arrangement, and may carry its own `sequence` for that day without changing the song.
- `position` is `pre`, `during` or `post`. `length` is in seconds.
- A plan saved without a date is a template.

### What the design leaves room for

None of the following is built by this decision. The formats are shaped so that each can be added without changing existing files.

- **Integrations with planning systems.** A plan is one self-contained file, and every item carries `externalIds`. An integration reads a plan from another system, matches songs by identifier instead of by title, and writes a `.plan.json`. The first targets are Planning Center and the project's sibling system, Global Connect.
- **Cloud sync and remote scheduling.** One file per item, stable identifiers and deterministic output mean a sync service moves whole files and detects real conflicts. Nothing in the files assumes a single computer.
- **Following a playback timeline.** When a band plays to tracks launched from a digital audio workstation such as Ableton Live, lyrics should advance with the music. Sections have stable identifiers that an external cue (MIDI, timecode or a network message) can address. An arrangement can later gain an optional `timeline` that places each section, or each line, at a position in beats, so the lyrics follow the tempo of the session.
- **Lyric following by audio, live captions and deep links** to a song or section, for the same reason: every addressable thing has a stable identifier.

## Alternatives considered

- **OpenLyrics as the native format.** Open and well designed, but it has one order per song and no themes, media, presentations or plans. It is supported for import and export.
- **Storing slides in the song.** What most presentation software does. Rejected: it is the cause of re-splitting lyrics for each screen.
- **Rich text per slide.** Rejected: it ties content to one look and makes every conversion lossy.
- **One language per song file, linked to its translations.** Rejected: lines drift out of step, which is the problem bilingual churches have today.

## Consequences

- One song serves the main screen, a broadcast overlay and a stage display, each with its own theme.
- Automatic slide breaks must be good, because operators will rely on them. Balanced wrapping and sensible grouping are core work, not polish.
- The lyric editor edits sections and lines, not slides. Operators coming from other software will need a clear preview of how a theme will split a song.
- Importers from slide-based formats must merge slides back into sections; some manual `breakAfter` marks will be needed to keep an author's intent.
- Every format needs code for unknown-field preservation and deterministic output from its first version. That foundation is built once in `GSSCore`.
- The examples above are the reference until JSON Schema files are published alongside each format's implementation.
