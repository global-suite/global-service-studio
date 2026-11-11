---
name: gss-core-rules
description: "Trigger: GSSCore, Sources/GSSCore, data model, core types, Swift package. Keep GSSCore portable, macOS 13 compatible, universal and tested."
license: MIT
metadata:
  author: global-suite
  version: "1.0"
---

## Activation Contract

Load this skill before changing anything under `Sources/GSSCore` or `Tests/GSSCoreTests`.

## Hard Rules

- Import Foundation only. No AppKit, SwiftUI, Metal, AVFoundation or other Apple UI or media framework.
- Target macOS 13. Use no newer API (`@Observable`, Observation, SwiftData and so on) without `if #available` and a working fallback.
- Build and run on both `arm64` and `x86_64`.
- Make public types `Equatable` and `Sendable`, as the existing types are.
- Put no user-facing text in `GSSCore`; report errors as typed values.
- Ship every behavior change with tests in the same pull request.
- Use invented placeholder text in tests: no copyrighted lyrics, Bible text, fonts or media.
- Write code, comments and test names in English.

## Decision Gates

| Change | Also load |
|---|---|
| A file format or its validation | `gss-file-formats` |
| Strings the user will see | `gss-localization` |
| Anything the render engine reads | `gss-render-path` |

## Execution Steps

1. Read the module's place in [docs/architecture.md](../../docs/architecture.md).
2. Change the code and add tests for the behavior it changes.
3. Run `swift build` and `swift test`.
4. If `swift test` fails with `no such module 'XCTest'`, run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.

## Output Contract

Report the changed types, the tests added, and the exact output of `swift build` and `swift test`.

## References

- [AGENTS.md](../../AGENTS.md): rules that are easy to break, commands
- [docs/architecture.md](../../docs/architecture.md): modules and what each may import
- [ADR 0002](../../docs/adr/0002-minimum-macos-13.md): macOS 13 and universal binary
- [CONTRIBUTING.md](../../CONTRIBUTING.md): code rules
