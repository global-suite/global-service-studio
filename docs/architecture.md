# Architecture

This document describes the intended structure. Only `GSSCore` exists today; the other modules are added as the [roadmap](roadmap.md) reaches them. The reasons behind the choices are in the [decision records](adr/README.md).

## Modules

Each module is a Swift package target. Dependencies point downwards only.

```
        GSSApp            operator interface: windows, slide grid, editor
           │
   ┌───────┼────────┬──────────────┐
GSSRender  GSSLibrary  GSSRemote   GSSIntegrations
   │           │          │              │
   └───────────┴────┬─────┴──────────────┘
                 GSSCore
```

| Module | Responsibility | May import |
|---|---|---|
| `GSSCore` | Data model, file formats, migrations, layer rules | Foundation only |
| `GSSLibrary` | Library folder, search index, importers and exporters; see [ADR 0007](adr/0007-library-storage-and-sync.md) | Foundation, SQLite |
| `GSSRender` | Compositing and output to displays | Metal, AVFoundation, Core Text, Core Animation |
| `GSSRemote` | Local HTTP and WebSocket API, device discovery | Network.framework |
| `GSSIntegrations` | Optional outputs and devices: NDI, Syphon, SDI, MIDI | Vendor SDKs |
| `GSSApp` | The application: windows, menus, editing, localization | AppKit, SwiftUI |

`GSSCore` importing only Foundation is a rule, not a preference. It is what lets the future iPhone remote, and any possible port, reuse the model.

## The output model

An output is what one screen shows. Every output is composited from a fixed stack of layers, from bottom to top:

| Order | Layer | Shows |
|---|---|---|
| 1 (bottom) | Screen color | The base color of the screen |
| 2 | Video input | A live camera or capture device |
| 3 | Media | Background images and videos |
| 4 | Slide | Lyrics, text and shapes of the current slide |
| 5 | Announcements | A second presentation that runs independently |
| 6 | Props | Persistent overlays such as a logo |
| 7 | Messages | Short text and timers sent on demand |
| 8 (top) | Mask | Shapes that hide part of the output |

This order is defined once, in `OutputLayer` in `GSSCore`.

Three concepts build on the stack:

- **Look**: which layers each output shows. The audience screen might show everything, while a broadcast feed shows only slides and props over transparency.
- **Clear group**: a set of layers cleared together with one action.
- **Stage display**: an output with its own layout for people on stage: current and next slide, clock, timers and messages.

Chroma key and alpha key output are ways of sending a look: the layers are rendered over a key color, or as separate fill and key signals, for a video switcher to overlay on camera.

## The render engine

- One render loop per output, driven by that display's refresh rate.
- Video is decoded by AVFoundation into textures that Metal composites directly, without copying frames through the CPU.
- Text is laid out by Core Text and cached as textures; it is re-rendered only when the slide or the theme changes.
- The operator interface never blocks the render loop. Editing a slide while it is live must not drop a frame.
- Output windows are separate from the operator window and survive a display being disconnected and reconnected.

Performance is judged on the slower supported machine, an Intel Mac from 2017, not on Apple silicon.

## Data

User content is stored as versioned JSON files in a library folder, with a rebuildable SQLite index for search. See [ADR 0004](adr/0004-open-file-formats.md). The files themselves are designed in [ADR 0005](adr/0005-file-format-design.md): songs store sections and lines without slide breaks, and themes decide how they are split and styled.

The library folder layout, the GRDB and FTS5 search index, how it stays consistent with the files and how the library is prepared for sync are decided in [ADR 0007](adr/0007-library-storage-and-sync.md).

## Localization

English is the base language and Spanish ships alongside it from the first release. No user-facing string is hard-coded. See [localization](localization.md).
