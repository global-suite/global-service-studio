# 0002. Support macOS 13 Ventura and later, on Apple silicon and Intel

- Status: Accepted
- Date: 2026-11-11

## Context

Many churches run their presentation computer for a decade. Commercial alternatives have moved their minimum to macOS 14, which leaves Macs from 2017 behind. Supporting those machines is one of the reasons this project exists.

Facts that bound the decision, as of November 2026:

- macOS 13 Ventura is the last version for the 2017 MacBook Pro and 2017 iMac.
- macOS 12 Monterey is the last version for the 2017 MacBook Air.
- macOS 26 Tahoe is the last version that runs on Intel Macs. macOS 27 is Apple silicon only.
- Xcode 27 builds for macOS 12 and later, and still produces `x86_64` binaries.
- The project's test hardware is an Apple silicon Mac mini and a 2017 MacBook Pro on Ventura.

## Decision

- The deployment target is **macOS 13.0**.
- Every release is a **universal binary**: `arm64` and `x86_64`.
- A release is tested on Apple silicon and on an Intel Mac running macOS 13 before it ships.

## Alternatives considered

- **macOS 12.** Would add the 2017 MacBook Air. Rejected: the project has no machine to test it on, and a platform that is not tested is not supported. It would also give up SwiftUI APIs introduced in macOS 13.
- **macOS 14 or later.** Would allow the Observation framework and SwiftData and simplify the code. Rejected: it drops every 2017 Mac, which defeats the purpose.

## Consequences

- No `@Observable`, SwiftData or other macOS 14+ API without an availability check and a fallback. State uses `ObservableObject`.
- Rendering must perform on 2017-era Intel and AMD GPUs, not only on Apple silicon. Performance work is measured on the Intel test machine.
- Rosetta is not a substitute for testing on Intel hardware: it does not reproduce an Intel GPU.
- Intel support has an end date outside the project's control. When Apple's tools stop building for `x86_64` or for macOS 13, the last compatible release will stay available for those Macs, and a new ADR will raise the minimum.
