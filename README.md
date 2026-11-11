# Global Service Studio

**Free, open source, native macOS presentation software for churches and live services.**

Lyrics, slides, images, videos and chroma-key overlays, sent to every screen in the room from one Mac.

> **Status: pre-alpha.** The project is being set up. There is no usable build yet. See the [roadmap](docs/roadmap.md) for what comes first.

## Why

- **Native.** Swift, AppKit, SwiftUI and Metal. No web runtime, so it gets the most out of Apple hardware.
- **Runs on older Macs.** macOS 13 Ventura or later, on Apple silicon and Intel. A 2017 MacBook Pro is a supported machine.
- **Free and open.** MIT licensed. No subscription, no seats, no account.
- **Open formats.** Your songs and services are plain, documented files that you own.
- **English and Spanish** from the first release.

## What it will do first

The first milestone is a complete basic Sunday service:

- A song library with verses, choruses and reusable arrangements
- Playlists for the order of service
- A slide grid you click to go live
- One full-screen audience output
- Image and video backgrounds
- Themes, and one key to clear the screen

Stage displays, multiple outputs, chroma key, a phone remote and broadcast outputs follow. The full plan is in the [roadmap](docs/roadmap.md) and the [feature map](docs/feature-map.md).

## Requirements

| | |
|---|---|
| To run | macOS 13 Ventura or later, Apple silicon or Intel |
| To build | Xcode 26 or later |

## Build from source

```bash
git clone https://github.com/global-suite/global-service-studio.git
cd global-service-studio
swift build
swift test
```

## Documentation

| Document | What it covers |
|---|---|
| [Roadmap](docs/roadmap.md) | Phases, and what is open for contributors |
| [Feature map](docs/feature-map.md) | Every planned feature and its phase |
| [Architecture](docs/architecture.md) | Modules, the render engine, the output layers |
| [Decisions](docs/adr/README.md) | Why the stack and the rules are what they are |
| [Song import strategy](docs/song-import.md) | How songs get in without a SongSelect integration |
| [Localization](docs/localization.md) | How English and Spanish strings are managed |
| [Releasing](docs/releasing.md) | Versions, tags and release notes |

## Contributing

Contributions are welcome. This project is **issue-first**: open an issue, wait for a maintainer to mark it `status:approved`, then open a pull request that links it.

Read [CONTRIBUTING.md](CONTRIBUTING.md) before you start. AI-assisted work is allowed under the [AI policy](AI_POLICY.md). Everyone is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md). Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

Questions go to [Discussions](https://github.com/global-suite/global-service-studio/discussions), not issues.

## License

The code is available under the [MIT License](LICENSE).

The Global Service Studio name and logo are covered by the [Trademark Policy](TRADEMARKS.md): forks are welcome, but they need their own name and branding.

Global Service Studio is an independent project. It is not affiliated with, sponsored by, or endorsed by Renewed Vision, CCLI, or any other vendor mentioned in this repository.
