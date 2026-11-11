# Roadmap

The order is deliberate: each phase produces something a church can use on its own. Dates are not promised. The [feature map](feature-map.md) lists every feature and the phase it belongs to.

| Phase | Name | Outcome | Status |
|---|---|---|---|
| 0 | Foundations | A repository anyone can build and contribute to | In progress |
| 1 | Basic Sunday | Run a full service on one screen | Next |
| 2 | Real church | Stage display, several screens, overlays | Planned |
| 3 | Control | Phone remote, API, macros | Planned |
| 4 | Production | Broadcast outputs and live inputs | Planned |
| 5 | Ecosystem | Integrations and multi-computer setups | Planned |

## Phase 0: Foundations

- [x] License, trademark policy, contribution rules
- [x] Issue forms, pull request template, policy checks
- [x] Continuous integration
- [x] Stack and platform decisions recorded
- [ ] Xcode app target, signed and notarized build pipeline
- [ ] Localization pipeline with English and Spanish
- [x] File formats designed: songs, themes, presentations and service plans ([ADR 0005](adr/0005-file-format-design.md))
- [ ] File formats implemented in `GSSCore`

## Phase 1: Basic Sunday

The first usable release. One operator, one Mac, one audience screen.

- Song library with search
- Lyric editor that splits pasted text into slides and labels verses and choruses
- Song arrangements
- Playlists for the order of service
- Slide grid: click a slide to send it live
- One full-screen audience output on a chosen display
- Image and video backgrounds
- Themes for consistent text styling
- Clear actions for slide, background and everything
- Presentations with free-form slides: text, images, shapes
- Import of plain text and OpenLyrics songs
- English and Spanish interface

## Phase 2: Real church

- Stage display with current and next slide, clock and messages
- Timers and countdowns
- Several outputs, each with its own look
- Props and messages
- Chroma key output
- Import from other presentation software and from slide decks
- CCLI license number and song credits on slides, and a usage log to export

## Phase 3: Control

- Local remote-control API
- Remote app for iPhone
- Macros and slide actions
- Keyboard shortcuts and control surfaces

## Phase 4: Production

- NDI and Syphon output
- Alpha key output: separate fill and key
- Live video inputs
- MIDI and DMX control
- Announcements layer running an independent presentation

## Phase 5: Ecosystem

- Service planning integrations
- Linking several computers
- Timeline and timecode
- Edge blending and masks
- Bibles, starting with public domain translations and an import system

## Not planned

- A Windows or Linux version. See [ADR 0001](adr/0001-native-swift-stack.md).
- Bundling copyrighted song lyrics or Bible translations.
- Accounts, subscriptions or telemetry that identifies a church.

## How to help

Issues labelled [`up-for-grabs`](https://github.com/global-suite/global-service-studio/issues?q=is%3Aissue+is%3Aopen+label%3Aup-for-grabs) are approved and unclaimed. For anything larger, open a feature request first; see [CONTRIBUTING.md](../CONTRIBUTING.md).
