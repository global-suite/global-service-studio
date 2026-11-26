# 0012. Concurrency policy

- Status: Accepted
- Date: 2026-11-25

## Context

The app runs live services. A frozen operator window or a stalled screen is seen by the whole room, and the slowest supported machine is a 2017 Intel Mac on macOS 13 ([ADR 0002](0002-minimum-macos-13.md)). [ADR 0006](0006-extensibility-and-live-performance.md) already says that the render path is closed, that the output never waits, and that anything slow is prepared before an item goes live. The code does not yet enforce any of this:

- **No compiler protection against data races.** The package is in Swift 5 language mode (`Package.swift:27`), and `AppState` is an `ObservableObject` that is not bound to the main actor (`Sources/GSSApp/AppState.swift:129`). Main-thread access is a convention.
- **Slow work on the main thread.** `perform` runs on the main thread and reads, decodes and writes files there: adding a song or a presentation to the service (`AppState.swift:307`, `:314`), choosing the library folder (`:341`), saving and opening songs (`:348`, `:354`, `:360`), listing plans when the app opens (`:393`), saving the service (`:398`), rewriting a presentation (`:432`), reading a service file (`:466`) and resolving a plan against the library (`:475`). A slow disk, or a file that iCloud has to download first, freezes the operator window.
- **The outputs share the main thread.** The output windows are SwiftUI views in an `NSHostingView` (`Sources/GSSApp/AudienceOutput.swift:228`) that observe `AppState` directly (`AudienceOutput.swift:74`). Any main-thread stall freezes the screens too, so in practice the render path is the main thread today.

There are good foundations to build on. The library index and media lists load on serial queues and return to the main thread with their results, and a load counter drops a result that arrives after a newer one (`AppState.swift:183`, `:211`). `SlideImageCache` and `MediaThumbnails` are actors (`Sources/GSSApp/SlideImageCache.swift:9`, `Sources/GSSApp/MediaThumbnails.swift:14`).

The study that led to this decision, [MxU Slides as an architecture reference](../research/mxu-architecture.md), lists these as its first three stability risks. This record states the rules in our own terms; it takes no code from MxU Slides.

## Decision

### Rules

1. **Swift 6 language mode for every target.** The migration goes one module at a time, each in its own pull request with the tests green: `GSSCore` first, then `GSSLibrary`, then `GSSApp` and the executables. Each step sets the language mode on its targets, and the package-wide Swift 5 setting is removed with the last one. New targets start in Swift 6 mode.
2. **All interface state lives on the main actor.** `AppState`, view models and controllers are `@MainActor`. State stays `ObservableObject`: the Observation framework and `@Observable` need macOS 14 ([ADR 0002](0002-minimum-macos-13.md)). Swift 6 language mode does not.
3. **The main actor never does file, network, database or decoding work.** A command changes in-memory state and hands slow work to an actor or a dedicated serial executor. The result comes back to the main actor as a value, and a result that arrives after a newer request is dropped, as the load counters already do.
4. **Everything an item needs to go live is prepared before it goes live** ([ADR 0006](0006-extensibility-and-live-performance.md), performance rule 3). Opening a plan resolves its songs, presentations and media off the main actor; going to a slide only reads what is already in memory.
5. **State crosses threads only as `Sendable` values.** Reference types are not shared between threads unless they are actors or guard their state themselves. The outputs read an immutable snapshot of what to show, never state that another thread is changing.
6. **Real-time threads never wait.** Code on an audio callback or a display-link or render callback does not wait on a lock, does not allocate memory on purpose, and does not call Swift concurrency or the main thread. State shared with those threads uses a try-lock that skips the work when the lock is busy, or atomics. The app has no such callback yet; the rule applies from the first one, such as audio routing for video sound ([ADR 0008](0008-media-layer-key-output-and-video.md)).

### Enforcement

- **The compiler.** Swift 6 language mode turns data races into compile errors. A module is not migrated while it needs `@unchecked Sendable` or `nonisolated(unsafe)` without a comment that explains why it is safe.
- **A test for blocking calls.** A test in `GSSAppTests` reads the sources of `GSSApp` and fails when a known blocking call, such as `Data(contentsOf:)`, `write(to:)` or `Library.open`, appears in main-actor code. The list grows when a new blocking call is found.
- **Thread Sanitizer in CI.** The test suite also runs with Thread Sanitizer on every pull request.

### What this record does not decide

How the outputs are drawn is decided in a separate ADR, after the current SwiftUI outputs are measured on the Intel test machine. This record only requires that, once that ADR is accepted, a stall of the main thread cannot stall the outputs.

## Alternatives considered

- **Keep Swift 5 mode and rely on review.** No migration cost, but races stay invisible until they happen during a service, and review cannot see which thread a line runs on. Rejected.
- **The Observation framework and `@Observable`.** Finer updates and less code, but it needs macOS 14 and would drop the 2017 Macs ([ADR 0002](0002-minimum-macos-13.md)). It can be adopted behind an availability check when it brings a measured benefit.
- **One global serial background queue for all slow work.** Simple, but a slow import would delay a plan that is about to go live, and nothing stops code from calling the main thread from it. Actors and executors per concern keep unrelated work apart.
- **Locks instead of actors.** Locks are still the right tool on real-time threads (rule 6). Elsewhere they hide waits, can deadlock, and are invisible to the compiler's checks.
- **Migrating the whole package at once.** One very large pull request, hard to review, and any regression would be hard to place. Module by module keeps each step under the pull request size limit where possible.

## Consequences

- The migration costs time and touches many files, and some features slow down while it runs. `GSSCore` is mostly value types and should be cheap; `GSSApp` is the expensive step.
- Some system and third-party types are not `Sendable` and need small wrappers or a value copy before they cross threads.
- Races become compile errors instead of rare failures during a service.
- A slow disk or an evicted iCloud file can no longer freeze the operator window. Once the output rendering ADR lands, it cannot freeze the screens either.
- Commands that load or save finish later than the call that starts them. The interface needs loading states, and tests of those commands become `async` and wait for the result.
- The blocking-call test is a text check, not a proof. It catches the known cases; review and Thread Sanitizer catch the rest.
- Thread Sanitizer makes the CI run slower.
- Contributors must learn these rules before touching `GSSApp`. `docs/CODEBASE-GUIDE.md` should point to this record.
