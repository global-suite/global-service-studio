# Roadmap

The order is deliberate: each phase produces something a church can use on its own. Dates are not promised. The [feature map](feature-map.md) lists every feature and the phase it belongs to.

| Phase | Name | Outcome | Status |
|---|---|---|---|
| 0 | Foundations | A repository anyone can build and contribute to | In progress |
| 1 | Basic Sunday | Run a full service on the screens a church already has | Next |
| 2 | Real church | Overlays, timers, importers from other software | Planned |
| 3 | Control | Phone remote, API, macros | Planned |
| 4 | Production | Broadcast outputs and live inputs | Planned |
| 5 | Ecosystem | Integrations and multi-computer setups | Planned |

## Phase 0: Foundations

- [x] License, trademark policy, contribution rules
- [x] Issue forms, pull request template, policy checks
- [x] Continuous integration
- [x] Stack and platform decisions recorded
- [x] File formats designed: songs, themes, presentations and service plans ([ADR 0005](adr/0005-file-format-design.md))
- [x] Song, theme and presentation formats implemented in `GSSCore`
- [x] Extensibility and live performance rules recorded ([ADR 0006](adr/0006-extensibility-and-live-performance.md))
- [ ] Xcode app target, signed and notarized build pipeline
- [ ] Localization pipeline with English and Spanish

The service plan format and the library folder layout are designed but built later, in Phase 1 step 7, when the interface that uses them exists.

## Phase 1: Basic Sunday

The first usable release. One operator and one Mac driving the screens of a typical service: a center screen, side screens and a teleprompter for the stage, with lyrics also sent to a video switcher for the live stream. Every church arranges its screens differently, so outputs are configured, not fixed.

Work happens in this order. Each step ends with something that can be seen running.

1. **Operator window design.** Close to what operators of existing presentation software expect, more modern, with very simple views. Done: two modes, Live and Prepare, and a design system, in [`design/`](../design/system.md).
2. **App skeleton.** The application target, the main window, English and Spanish.
3. **First projection, end to end.** One song with a theme, full screen on a second display, with lines split and balanced automatically. Measured on the Intel test machine before anything is built on top.
4. **Outputs.** Any number of outputs, each assigned to a display, each with a role and its own theme:
   - *Audience*: what the room sees, on one screen or several.
   - *Stage*: a teleprompter view with the current and next lines, a clock and messages.
   - *Key*: lyrics over a key color for a video switcher to overlay on camera.
5. **Media.** Image and video backgrounds, then full-screen video with sound and playback controls, and images.
6. **Documents.** PDF files first. Keynote and PowerPoint decks after an investigation into how faithfully they can be imported.
7. **The order of service.** Song library with search, the lyric editor, arrangements, playlists, and the service plan and library formats that back them.

Lyrics are shown in one language in this release. The interface is in English or Spanish, chosen in Settings.

Also part of this release:

- Slide grid: click a slide to send it live
- Clear actions for slide, background and everything
- Presentations with free-form slides: text, images, shapes
- Import of plain text and OpenLyrics songs
- Keyboard shortcuts for running a whole service
- A locked Live mode for volunteers: run the service without editing or leaving Live

### Reliability gate

Maturity comes before quantity: a feature enters only when it is stable, tested and recoverable after a failure. Before the first release, and before any Phase 1 feature that is not already in progress, the app must:

1. Keep file, database and decoding work off the main thread, with the compiler checking it ([ADR 0012](adr/0012-concurrency-policy.md)).
2. Measure the outputs on the Intel test machine, and keep them running when the operator window stalls.
3. Log what happens, detect a stalled main thread, and let the operator build a problem report that stays on the Mac until they send it.
4. Resume a service after a crash, autosave without overwriting changes made elsewhere, watch the library folder, back it up on a schedule, and relink missing media ([ADR 0013](adr/0013-recovery.md)).
5. Put limits on every importer, so a damaged or hostile file cannot stop the app.
6. Ship as a signed, notarized app.
7. Run a two-hour service on the Intel test machine without a dropped frame, and run the tests with the thread sanitizer and on Intel.

Features already built stay, and must pass the same gate. The reasons and the evidence are in the [architecture research](research/mxu-architecture.md).

## Phase 2: Real church

- Bilingual lyrics: show a song in two languages at once, or choose the language for each output. The song and theme formats already store what this needs, so no library has to be migrated
- Timers and countdowns
- Props and messages
- Looks: choose which layers each output shows
- Import from other presentation software
- CCLI license number and song credits on slides, and a usage log to export
- Editing imported decks inside the app

## Phase 3: Control

- Local remote-control API, reachable only from the same Mac until local network access is turned on
- Web remote that runs in any phone's browser, then a native iPhone app
- Macros and slide actions
- Keyboard shortcuts and control surfaces

## Phase 4: Production

- NDI and Syphon output
- Alpha key output: separate fill and key
- Live video inputs, for churches that mix lyrics over camera on the Mac instead of on a switcher
- MIDI and DMX control
- Announcements layer running an independent presentation

## Phase 5: Ecosystem

- Integrations, in this order: Planning Center, OBS, and Global Connect, the church management system built alongside this project
- Campus link: the computers of one campus (projection, stage, a laptop for the speaker, a laptop for the band) share one library of songs, themes and templates over the local network, each keeping a full copy that works offline. A computer can follow the live service or run at its own pace. Syncing through the internet is decided after the local link works, and sharing a library between churches is an idea for later
- Timeline and timecode
- Edge blending and masks
- Bibles, starting with public domain translations and an import system

## Not planned

- A Windows or Linux version. See [ADR 0001](adr/0001-native-swift-stack.md).
- Bundling copyrighted song lyrics or Bible translations.
- Accounts, subscriptions or telemetry that identifies a church.

## How to help

Issues labelled [`up-for-grabs`](https://github.com/global-suite/global-service-studio/issues?q=is%3Aissue+is%3Aopen+label%3Aup-for-grabs) are approved and unclaimed. For anything larger, open a feature request first; see [CONTRIBUTING.md](../CONTRIBUTING.md).
