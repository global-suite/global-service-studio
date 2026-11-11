# 0001. Build a native app with Swift, AppKit, SwiftUI and Metal

- Status: Accepted
- Date: 2026-11-11

## Context

Global Service Studio drives live video output during a service. It composites text, images, video and live inputs onto several screens in real time, and a dropped frame or a stall is visible to the whole room. It must also run well on Macs from 2017, where memory and GPU power are limited. A phone remote is planned, so some code should be shareable with iOS.

The project is macOS-only today. A Windows version is a possibility, not a commitment.

## Decision

Build a native macOS application in Swift:

| Concern | Technology |
|---|---|
| Language | Swift |
| Operator interface | AppKit as the shell, SwiftUI for panels and forms |
| Output rendering | Metal, with Core Animation and Core Text |
| Video and audio | AVFoundation, Core Audio |
| Persistence | Versioned files plus a SQLite index (see [ADR 0004](0004-open-file-formats.md)) |
| Networking and remote control | Network.framework, Bonjour, a local HTTP and WebSocket API |
| Structure | Swift packages, one per module (see [architecture](../architecture.md)) |
| Distribution | Developer ID signing and notarization, outside the Mac App Store |

The data model and file formats live in a module, `GSSCore`, that imports no Apple UI or media framework.

## Alternatives considered

- **Electron or Tauri.** Fastest way to a cross-platform app, and how some open source projects in this space are built. Rejected: a web runtime costs memory and startup time on older Macs, and gives less control over multi-display, frame-accurate video output.
- **Qt and C++.** A real cross-platform native option. Rejected for now: it only pays off if Windows becomes a goal, it feels less at home on macOS, and it raises the barrier for contributors.
- **Flutter or React Native.** Not designed for a real-time, multi-display compositing engine.
- **SwiftUI only.** Rejected as the shell: on macOS 13 it lacks the control needed for the slide grid, window management across displays and keyboard handling. It is used where it fits.

## Consequences

- The app can use hardware video decoding and the GPU directly, on both Apple silicon and Intel.
- The remote app for iPhone can reuse `GSSCore` and the networking code.
- Contributors need a Mac and Xcode.
- A Windows version would require rewriting the interface, the render engine and media playback. `GSSCore`, the file formats and the remote API would carry over, which is why `GSSCore` must stay free of Apple-only frameworks.
- Distributing outside the Mac App Store avoids sandbox limits on broadcast SDKs and MIDI, and requires a paid Apple Developer account for signing and notarization before the first public release.
