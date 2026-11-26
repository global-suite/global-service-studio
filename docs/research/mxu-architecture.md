# MxU Slides as an architecture reference for Global Service Studio

- **Date:** 2026-11-25
- **Reference:** `MxU-Engineering/mxu-slides`, commit `003be6238f2bf0508b071ed4a8bc5628d7bcbfa3` (2026-11-01), read in a temporary directory outside this repository. About 230k Swift lines.
- **GSS baseline:** `main` at `46156bf`, 66 Swift source files in `Sources/`. Every GSS `path:line` below refers to that commit.
- **Licence boundary.** MxU is PolyForm Shield 1.0.0 and GSS (MIT) competes with it. Nothing in this report is code, and nothing here may be turned into a copy, an adaptation or a paraphrase of MxU code. Evidence is given only as `path:line` in the MxU tree, so a reader can check a claim; every recommendation is described in our own terms and has to be designed from our own requirements. Where an idea is common industry practice (XPC services, watchdogs, token scopes), the report says so, because that is what we take: the practice, not their implementation.
- **Method.** Four read-only passes covered MxU by area and one covered GSS; the claims that drive recommendations were spot-checked. Each "Not verified" note marks a claim that was inferred but not opened.
- **Tracked in** [#148](https://github.com/global-suite/global-service-studio/issues/148).

**Guiding principle:** maturity before quantity. A feature that enters must be stable, tested and recoverable after a failure, even if that means fewer features.

## Summary

1. **What MxU does better than GSS today is not features, it is operational discipline.** It isolates closed SDKs in XPC services that reconnect on their own, watches its main thread ten times a second and records a stack when it stalls, writes breadcrumbs to disk, detects that the last run crashed, makes nightly backups, relinks missing media by content hash, and has a soak mode whose pass criterion is zero dropped frames. GSS has none of these yet.
2. **GSS is ahead on contracts and principles.** Open, documented, deterministic file formats (ADR 0004/0005), a written live-performance rule set (ADR 0006), a rebuildable index with a change journal already in place (ADR 0007), English and Spanish from day one, macOS 13 and Intel support, and CI. MxU has no localisation, thin accessibility, no CI in the repository, and binds its API to every network interface with `Access-Control-Allow-Origin: *`.
3. **The largest risk in GSS today is the main thread.** File reads, decoding, plan resolution and saves happen inside `AppState.perform` on the main thread, `AppState` is not `@MainActor`, the package is in Swift 5 language mode, and the audience output is drawn by SwiftUI on that same main thread. A slow iCloud folder can freeze the operator window and the screens together. Nothing records that it happened.
4. **MxU uses Automerge mostly for undo, history and editor checkouts, not for cloud sync.** No sync transport or server was found. This matters for the data decision in section 5.
5. **MxU has no AI features.** Its "smart" features are deterministic heuristics with golden fixtures. That is a good model for GSS too.

Next step, accepted by the owner (O2): a **reliability gate** inside Phase 1, before more Phase 1 features (sections "Stability risks" and "Roadmap").

## 1. Stability

### 1.1 Process isolation

**How MxU does it.**
- Closed vendor SDKs (NDI, Blackmagic DeckLink) run in embedded XPC services, not in the app (`apps/mac/project.yml:75-78`, `:121-144`, `:166-185`). The NDI library is loaded at runtime inside the helper only, and is skipped cleanly if it is not installed (`apps/mac/project.yml:130-139`; `apps/mac/Packages/NDIKit/Sources/NDIKit/NDILibrary.swift:25-61`). Only the helpers carry the `disable-library-validation` entitlement (`apps/mac/Signing/Helper.entitlements`); the main app does not.
- The multitrack audio player is a separate executable launched by the app and driven over a local socket (`apps/mac/Sources/TracksController.swift:138-155`). A dead player is detected by checking its process, and its crash report is located and logged (`:120-136`). Not verified: how it is relaunched.
- **Reconnection pattern** (`apps/mac/Sources/DeckLinkOutputController.swift:91-152`): each connection gets a generation number; callbacks from an older generation are ignored. On interruption, the app reopens the output with the parameters it saved, so the restarted helper receives the state again. On invalidation it records a diagnostic event and marks the output failed.
- **Delivery watchdog** (`apps/mac/Sources/DeckLinkOutputController.swift:347`, `:395-428`): every 2 s it checks whether frames were delivered in the last 3 s; if not, it reconnects, and after repeated "phantom" cycles it kills the wedged helper. No exponential backoff was found.

**GSS today.** One process. No closed SDK yet. ADR 0006 already says closed SDKs are optional modules behind an interface we own, and extensions never run in the app's process. Nothing says how a helper is supervised. **Gap.** The principle exists; the supervision contract does not. Without it, the first NDI or DeckLink module will be written ad hoc.

**Recommendation for GSS.**
- Write the supervision contract before the first helper: every out-of-process component (closed SDK output, untrusted file parser, extension host) is an XPC service or child process with (a) an idempotent "here is the full state" message the app can resend at any time, (b) a liveness signal measured by the app (frames or heartbeats delivered, not "connection open"), (c) a bounded restart policy with backoff and a visible state on the output chip ("Reconnecting", "Failed — click to retry"), and (d) a rule that the main output never waits for a helper.
- Use it first for **importers of untrusted files** (Keynote/PowerPoint/PDF conversion, ProPresenter later), which arrive in Phase 1, before any broadcast output in Phase 4. That gives the pattern a real, testable user early. Test the contract with a fake helper that crashes, hangs and floods, in CI.

### 1.2 Threads and concurrency

**How MxU does it.**
- Swift 6 language mode across the app and packages (`apps/mac/project.yml:11`; `apps/mac/Packages/AudioEngine/Package.swift:1`), so data races are compile errors. Target is macOS 14, arm64 only (`apps/mac/project.yml:12-13`). UI controllers are `@MainActor` and `@Observable`; XPC callbacks are `@Sendable` and hop to the main actor. Small shared state uses `OSAllocatedUnfairLock` (`apps/mac/Sources/DiagnosticsStore.swift:55-78`; `apps/mac/Sources/FollowController.swift:36`).
- **Real-time audio rule** (`…/AudioEngine/…/EngineStateLock.swift:3-43`): the lock that guards engine state asserts in debug builds if it is taken with waiting inside an audio callback; on the audio thread it is only ever *tried*, and the work is dropped if the lock is busy. A small C target provides atomics for the audio path (`apps/mac/Packages/AudioEngine/Package.swift:13-14`). This is standard real-time practice: never block the audio thread.
- Static "sweep" tests appear to audit that every XPC closure is `@Sendable` and checks the generation (`XPCClosureSweepTests`, `PerfHooksSweepTests` in PresenterCore tests). Not verified: their exact checks.

**GSS today.**
- `Package.swift:27` keeps `swiftLanguageModes: [.v5]`; no strict concurrency checking. `AppState` is an `ObservableObject` without `@MainActor` (`Sources/GSSApp/AppState.swift:129`); main-thread access is a convention, with results posted back through `DispatchQueue.main.async`.
- Synchronous file I/O inside `perform` on the main thread: adding to the service, opening a song, saving, listing and saving plans, rewriting a presentation, reading and resolving the service plan (`Sources/GSSApp/AppState.swift:307`, `:314`, `:348`, `:354`, `:360`, `:393`, `:398`, `:432`, `:466`, `:475`).
- Good foundations: `SlideImageCache` and `MediaThumbnails` are actors, video is prepared off the main thread, late results are discarded with load counters (`AppState.swift:183`, `:211`). Output windows are SwiftUI views on the main thread, with `AVPlayerLayer` for video (`Sources/GSSApp/AudienceOutput.swift`). No display link, no separate render thread.

**Gap.** The compiler cannot catch a race, and nothing stops a slow disk from freezing the screens. ADR 0006 says "the output never waits" and "the render path is closed", but in practice the render path *is* the main thread today.

**Recommendation for GSS (ADR 0012 "Concurrency policy").**
- Swift 6 language mode for every target (Swift 6 mode does not require macOS 14; only `@Observable` does, so `ObservableObject` stays). `AppState` and all view state on `@MainActor`. All file, index and decode work behind actors or a dedicated I/O executor; `perform` only mutates in-memory state and enqueues work. A rule, checked by a test that greps the app module, that `Data(contentsOf:)`, `write(to:)` and `Library.open` are not called from `@MainActor` code. **Migrate per module**: `GSSCore` first (pure value types, cheapest), then `GSSLibrary`, then `GSSApp`.
- **Output rendering** (decision O4: measure first): either keep SwiftUI for slides but make the output consume an immutable, pre-rendered snapshot so the main thread only swaps a layer's contents, or move the audience output to a `CALayer`/Metal path driven by a display link off the main thread. Measure on the 2017 Intel Mac before choosing.
- Adopt the real-time audio rule now, in writing, before Phase 1 video with sound grows into audio routing: no lock waits, allocations or Swift concurrency on audio callbacks.

### 1.3 Hang detection and diagnostics

**How MxU does it** (all in `apps/mac/Sources/DiagnosticsStore.swift` unless noted).
- A watchdog on a utility queue pings the main thread every 100 ms, starting 5 s after launch (`:81`, `:94-97`). A reply later than 250 ms is recorded as a hitch and published (`:237-246`).
- If the main thread is still stuck at about 120 ms, its stack is captured, with a follow-up capture at 1.5 s, a gate that limits how many captures are taken, the run-loop mode, and symbolication on another queue (`:82-85`, `:249-270`). Debug builds also run the system `sample` tool on long stalls, rate-limited (`:165-187`, `:220-225`). Capture can be switched off with a preference.
- A 60 s performance pulse records CPU, memory and peak memory, frame delivery (late, dropped, jumped), text rasterisation and hitches (`:100-162`). Extra meters count SwiftUI `body` re-evaluation storms and spins (`:41-43`); synthetic stalls verify that the detectors themselves work. MetricKit subscription (`:33`). `os.Logger` with categories per subsystem. Breadcrumbs are written to `~/Library/Application Support/MxU Slides/Diagnostics` (`:18-24`); the core package reports into them through an injected sink, so it does not depend on the app (`:36`). No `os_signpost` was found.

**GSS today.** No `os.Logger`, no breadcrumbs, no watchdog, no MetricKit. Errors become a localized `AppAlert` and the underlying error is dropped (`Sources/GSSApp/AppState.swift:310`, `:361`, `:467`). **Gap.** When a church reports "it froze during the second song", there is nothing to look at.

**Recommendation for GSS (ADR "Live-safety diagnostics").**
- `os.Logger` with fixed categories (library, output, media, import, api) from now on; every caught error is logged with its underlying cause before it becomes an alert.
- A **local breadcrumb journal**: a small, size-capped, rotated file of operator-level events ("went live: plan item 3, slide 2", "output 2 disconnected"), written off the main thread. It never leaves the Mac unless the operator sends it, consistent with "no telemetry that identifies a church" in the roadmap.
- A **main-thread watchdog** with a threshold tuned on the Intel Mac, recording hitches with their breadcrumb context. Stack capture can come later; the hitch count and timestamps already pay for themselves.
- `os_signpost` intervals around going live, text layout and media preparation, so Instruments shows the live path. This is cheap and MxU does not have it. The diagnostics core (journal, watchdog) belongs in a portable module with an injected sink, so `GSSCore` stays free of Apple UI frameworks.

### 1.4 Recovery

**How MxU does it.**
- **Last run crashed:** the app stores its launch date and looks for newer crash reports at the next launch; if found, the feedback entry changes to "quit unexpectedly" (`apps/mac/Sources/FeedbackController.swift:24-41`; `apps/mac/Sources/FeedbackView.swift:18`). Diagnostics older than 14 days are deleted (`…/DiagnosticsBundle.swift:18`). **Report a Problem** packages system details (OS, model, chip, RAM, free disk, displays, build commit) and the diagnostics into an archive (`apps/mac/Sources/FeedbackController.swift:49-60`, `:116-127`). Not verified: where it is sent.
- **Scheduled backups** (`ScheduledBackup`, `BackupBundle`; the test case is nightly at 3 AM keeping 7, `ScheduledBackupTests.swift:34`).
- **Missing media** is relinked by scanning a folder and matching content hashes, not names; unmatched items can be restored from tombstones, and the grid marks slides with missing media (`apps/mac/Sources/LocateMissingMediaView.swift:21`, `:78-99`; `apps/mac/Sources/AppModel.swift:2144-2207`; `apps/mac/Sources/PresentGridView.swift:1213`, `:1425`). No document autosave journal was found beyond window frames; edits go through Automerge documents (section 5).

**GSS today.**
- Atomic writes everywhere (`Sources/GSSLibrary/Library.swift:56`, `:76`; `LibraryPlans.swift:67`; `LibraryPresentations.swift:33`, `:77`). Index rebuilt if corrupt (`Sources/GSSLibrary/LibraryIndex.swift:39-41`, `:58-66`). Invalid files listed as problems in the sidebar. Missing plan references produce an alert listing them (ADR 0009). The change journal of ADR 0007 exists for songs (`LibraryIndex.swift:43-47`).
- No autosave of the service being run (`hasUnsavedServiceChanges` only, `AppState.swift:191`), no backups, no crash detection, no live-state restore, no folder watching (ADR 0007 rule 2 decided FSEvents; not built), no missing-media flow. ADR 0005 already stores a `sha256` next to every media path, so hash relinking is cheap for us.

**Recommendation for GSS (ADR 0013 "Recovery").**
- **Crash-safe live state:** persist, off the main thread and on every go-live, a tiny "where we are" record (plan id, item, slide, what each layer shows). On relaunch after a crash, offer "Resume the service where it stopped" and restore the outputs in one click. This is the single feature that most changes a crash from a disaster into an incident.
- **Autosave** of the open service plan and editors, with a short debounce and atomic writes, plus a conflict check (content hash at load vs on disk) before overwriting, so a file changed by a sync tool is never silently replaced. ADR 0007 rules 3-6 already describe the parts.
- **Scheduled local backups** of the library folder (excluding media, which is content-addressed), with retention and a one-click restore of a single item. Tested by restoring.
- **Missing media flow** using the stored hashes: mark affected slides, offer "Locate…", relink by hash. A missing font falls back visibly, never invisibly. **Report a Problem**: builds the archive locally (system facts, breadcrumbs, recent logs, crash reports) and lets the operator choose how to share it. No upload service is needed.

### 1.5 Soak and performance testing

**How MxU does it.**
- `AutoSoak` runs the app for N minutes from a launch argument, keeps the system awake with a latency-critical activity, takes a baseline, logs every 30 s, and **passes only with zero dropped frames after warm-up**, exiting 0/1/2 for pass/fail/abort (`apps/mac/Sources/AutoSoak.swift:7-63`). `MediaSoak` generates two synthetic loops once (4K ProRes 4444 with alpha, HEVC 1080p60) and plays them together, counting displayed and dropped frames, including at the loop seam (`apps/mac/Sources/MediaSoak.swift:22-40`).
- Test targets per package, stub test targets that build without the closed SDKs, Swift Testing, archive security tests (section 2). Golden fixtures for slide splitting live in `packages/make-slides-fixtures/`. No baseline performance tests and no CI configuration were found in the repository.

**GSS today.** Unit tests for Core (16 files), Library (5) and App (23); CI on `macos-15` running build and tests, actions pinned by SHA. `GSSVideoBench` measures video playback (ADR 0008). No soak, no x86_64 run, no Thread Sanitizer.

**Recommendation for GSS.**
- A **soak mode** (launch argument) that runs a generated service through every slide and media cue on a loop, with output frames counted and a pass criterion of zero dropped frames and zero main-thread hitches over a threshold. Run it for two hours on the 2017 Intel Mac before each release; record the result in the release checklist (`docs/releasing.md`). **Generated test media** at test time (never copyrighted media), as ADR 0008's benchmark already does.
- CI additions, cheap first: a Thread Sanitizer test run; an x86_64 build (`swift build --arch x86_64`); a large generated library (thousands of songs) for list and search timings, compared with a stored baseline and failing on a regression beyond a margin.
- **Golden fixtures for automatic slide breaks**: input lyrics plus theme limits produce an expected split. ADR 0005 says operators will rely on automatic breaks; fixtures are how that reliance is earned.

## 2. Security

### 2.1 Local API

**How MxU does it** (`apps/mac/Packages/LocalAPI/Sources/LocalAPI/`, `apps/mac/Sources/LocalAPIController.swift`).
- **Off by default** (`LocalAPIController.swift:80`, `:182-190`); port 6980, configurable (`:82`, `:193-203`). **Tokens:** random secrets with a recognisable prefix; only a salted SHA-256 and a short visible prefix are stored on disk (`APIScope.swift:48-68`, `:163-178`), in a JSON file in the library root (`LocalAPIController.swift:120-124`). The operator-copyable default key is in the Keychain (`:34-76`). Revocation deletes both (`APIScope.swift:188-199`).
- **Scopes:** three ordered levels, view < control < edit, shown to operators as Watch / Operate / Manage; every route declares its minimum and gets a 403 otherwise (`APIScope.swift:4-24`; `LocalAPIServer.swift:196`; `SettingsView.swift:688`).
- **WebSocket:** authenticated during the HTTP upgrade (401 on failure), then a hello message with the scope; every incoming message re-checks that the token still exists with the same scope, so **revoking a token cuts open sessions** (`APIWebSocketHandler.swift:10-13`, `:42`, `:133`).
- **Follow pairing:** a code shown on the host, five failed attempts invalidate it, success mints a control-scope token that the follower stores in its Keychain (`FollowMode.swift:121-166`; `FollowController.swift:116-153`, `:653-678`). Blob downloads validate the hash format before touching the file system (`LocalAPIServer.swift:151-152`). **Bonjour** advertises `_mxu-slides._tcp` while the API is on, named after the computer, TXT record with only a station id and name (`BonjourAdvertiser.swift:5`, `:50-64`).
- **Weaknesses we should not copy:** the server is created with a port only (`LocalAPIServer.swift:60`), so it listens on every interface; no TLS (`LocalAPIController.swift:214`); `Access-Control-Allow-Origin: *` with no `Origin` check (`LocalAPIServer.swift:242-249`), which lets any web page the operator visits call the API if it has a token, and probe unauthenticated routes; tokens accepted in the query string (`:222-225`), which leaks them into logs and history; token comparison is not constant-time (`APIScope.swift:59-62`, `:201-205`); no general rate limiting; `/v1/ping`, `/openapi.json` and `/docs` are unauthenticated and the docs page trusts the `Host` header (`LocalAPIServer.swift:99-121`).

**GSS today.** No network code at all. ADR 0006: off until enabled, pairing and permissions before it ships, versioned contract.

**Recommendation for GSS (ADR "Local API v1: security and events").**
- Off by default. When on, **loopback only by default**; LAN access is a second, explicit switch that explains who can reach it (decision O5).
- Scoped tokens with the same three-level idea (read, operate, manage) plus per-device names, last-used time and one-click revoke that closes live sockets. Store only salted hashes; compare in constant time. Secrets in the Keychain.
- Tokens only in the `Authorization` header or in the first WebSocket message, never in URLs. Browser clients (the phone web remote) use a short-lived ticket exchanged for the socket. **Origin allow-list** and no wildcard CORS. Unauthenticated endpoints limited to a version ping that reveals no names. Pairing by short code with attempt limits and expiry, as an alternative to copy-pasting keys; a phone pairs by scanning a QR code shown on the Mac.
- Rate limiting per token and per address; request size limits; the API server on its own actor, never on the main thread, consistent with ADR 0006.
- Bonjour advertises only when LAN access is on, with a service name and a random station id; no church name, no version. TLS is optional on a LAN and costly with self-signed certificates; record the decision, and do not send manage-scope tokens to non-loopback clients without it, or accept that risk explicitly.

### 2.2 Signing, notarization, sandbox, entitlements

**How MxU does it.** Developer ID signing with hardened runtime and timestamp, each nested binary signed separately, strict deep verification, notarization through `notarytool` with a Keychain profile, stapling of app and disk image (`apps/mac/scripts/release-dmg.sh:14-16`, `:70-102`). Not sandboxed. The app's entitlements are camera and audio input only (`apps/mac/Signing/MxUSlides.entitlements`); helpers carry library-validation exemption only. No in-app updater was found.

**GSS today.** A SwiftPM executable with no bundle, no `Info.plist`, no entitlements, no signing. Phase 0 still lists "Xcode app target, signed and notarized build pipeline" as open (`docs/roadmap.md:23`); the feature map promises signed, notarized builds with updates in Phase 1.

**Recommendation for GSS.**
- Close that Phase 0 item before the first release candidate: app bundle, hardened runtime, notarization in CI on tags, a minimal entitlement set (and no library-validation exemption in the main app, ever), plus a signed update feed (Sparkle with EdDSA signatures is the usual open option; record it as an ADR because it is a delivery dependency). **Sandbox** (decision O9): not sandboxed for 1.0, with hardened runtime and helpers isolated; revisit for a Mac App Store build. A sandboxed app with security-scoped bookmarks for the library folder is the stronger default, but complicates file access and NDI more than it helps today.

### 2.3 Untrusted third-party files

**How MxU does it.**
- PPTX and ProPresenter bundles are unzipped with the system `ditto` into a temporary directory, then the extracted tree is walked and **symbolic links are rejected** (`apps/mac/Packages/PPTXImport/…/PPTXArchive.swift:27-40`; `apps/mac/Packages/ProImport/…/ProPresenterImporter.swift:302-315`; `apps/mac/Packages/PresenterCore/…/Import/ImportArchiveValidation.swift:18-32`).
- OOXML part paths are normalised, must stay under the root, may not contain NUL or symlinks, checked before and after resolution (`…/PPTXPackage.swift:43-85`). XML is parsed with external entities disabled and **any DTD rejected**, which blocks entity expansion attacks (`…/PPTXPackage.swift:87-95`).
- ProPresenter files are protobuf; files over 32 MiB are skipped (`ProPresenterImporter.swift:210-211`); a garbage-bytes test exists. Security tests build malicious archives (`ProArchiveSecurityTests.swift:6-17`, `PPTXSecurityTests`). Gaps: no limit on total uncompressed size or entry count (zip bombs fill the disk), no fuzzing, parsing in-process.

**GSS today.** Plain text read whole with no size limit (`Sources/GSSApp/SongFile.swift:9`); OpenLyrics through `XMLParser` with default settings and no size or depth limits (`Sources/GSSCore/Import/OpenLyricsImporter.swift:43`, `:128`). ADR 0010 keeps imports away from the render path and turns slides into images.

**Recommendation for GSS (ADR "Untrusted input").**
- Limits for every importer: file size, uncompressed total, entry count, nesting depth, string length, slide count. Rejected input produces a clear, localised error and leaves the library unchanged.
- XML: external entities and DTDs refused; a test proves it. Archives: our own extraction to a fresh temporary directory with path containment, no symlinks, and size and count limits enforced while extracting, not after.
- **Run conversion out of process** (the first user of the supervision contract in 1.1), so a malformed deck can crash a helper, not the app. Keynote/PowerPoint conversion through other apps (ADR 0010) is already out of process by nature. Fuzz the parsers we own (OpenLyrics, plain text, our own JSON formats) with generated inputs in CI.

## 3. Simple but powerful

**How MxU does it.**
- Three modes in one window: Present, Edit and Scheduler, switched from one compact menu in the title bar (`apps/mac/Sources/AppShell.swift:4`, `:131`, `:381`, `:442`). Edit has four contexts on ⌘4-⌘7 (`AppShell.swift:18`, `:217-225`). Three columns: library sidebar, centre (grid or editor), and a right column whose panel sizes persist and can be torn off into windows (`AppShell.swift:237-242`, `:298-301`, `:363-375`, `:405-420`). Jumping from Present to edit something shows a "‹ Present" return button (`AppShell.swift:385-397`).
- The Present right column is nine optional modules (combos, timers, tracking, music, alerts, mixer, confidence, outputs, timecode) with a default order (`apps/mac/Sources/Modules/ServiceControlsModule.swift:3-20`). **Advanced features live as optional modules, not as main screens.**
- **Volunteer mode** is the key idea: a locked run-only mode, enabled first in settings, that hides editing and hover controls, limits visible modules and library kinds, blocks creating content and entering Edit, and logs blocked attempts (`apps/mac/Packages/PresenterCore/…/VolunteerModeLogic.swift:5`; `apps/mac/Sources/PresentLayoutController.swift:173-228`; `apps/mac/Sources/AppShell.swift:141`, `:521`; `…/KeyboardControl.swift:211-227`).
- Onboarding: two steps (content, then screens), with sample content and a "restore getting started" command (`…/Onboarding/OnboardingFlow.swift:4-6`, `:15`, `:38-42`; `apps/mac/Sources/OnboardingView.swift:106`, `:215`). Systematic empty states (`ContentUnavailableView` in 20+ places).
- Shortcuts: one catalogue of about 30 commands in 6 groups, each with a scope (present, editor, anywhere) and a flag for whether it works in volunteer mode; user-remappable with a key recorder; digits + Enter jump to a slide; a single letter jumps to a song section (`…/KeyboardControl.swift:71-77`, `:91-94`, `:105-136`, `:200-227`; `apps/mac/Sources/KeyboardShortcuts.swift:7-31`, `:139-163`, `:301`, `:333-346`). No command palette. Settings: 10 searchable categories, with "Advanced" tabs that explain consequences (`apps/mac/Sources/SettingsView.swift:593-646`; `apps/mac/Sources/StreamRecordSettings.swift:66-97`). Undo is history on Automerge documents, with a choice between the text field's undo and the document's (`…/Documents/EditorReplica.swift:44-56`; `apps/mac/Sources/SlideEditorView.swift:1322-1364`).
- Weak spots: no localisation at all, about ten accessibility labels, no reduce-motion support, dark theme forced by default (`AppShell.swift:302`).

**GSS today.** Two modes, Live and Prepare, designed on the canvas (`design/`), with a design system and window size classes. English and Spanish. Commands go through `AppState.perform(_:)`, which is the seed of a command model (ADR 0006 rule 1). Live only shows the service plan (owner rule). **Gap.** No locked operator mode, no shortcut catalogue (roadmap Phase 1 promises "keyboard shortcuts for running a whole service"), no onboarding or display setup flow, no undo model decided.

**Recommendation for GSS (ADR "Command catalogue and operator lock").**
- **One command catalogue** in the model layer: every operator action is a named command with a localised title, a default shortcut, a scope (Live, Prepare, anywhere) and a "safe for a locked operator" flag. The menu bar, shortcuts, a future command palette, the API, macros and the phone remote all read from it. This makes ADR 0006 rule 1 enforceable by a test ("every command has an API route").
- **Locked Live mode** for volunteers, in the first release (decision O8): Live without editing, with a short list of allowed commands, unlocked with a password or a long-press. Cheap once the catalogue exists, and probably the biggest single win for the "simple" goal.
- **First-run flow:** choose or create the library folder, detect displays and assign roles (audience, stage, key) with a test pattern on each, optional sample service with invented content. Each step is skippable and reachable later from Settings.
- **Progressive disclosure:** advanced areas (audio routing, timecode, MIDI, API) appear only when enabled in Settings, as optional panels in Live, never as new modes. **Undo:** built on the command model (each command records its inverse), scoped per document. No CRDT is needed for undo. Keep our lead: localisation, accessibility labels on every icon button, reduce motion, light and dark.

## 4. Integrations

### 4.1 Local API design

**How MxU does it.**
- One **declarative route table**: each entry declares method, path, minimum scope, operation id, summary, tag and response schema, and points to a bridge into the app (`apps/mac/Packages/LocalAPI/…/APIRouteTable.swift:65-69`, routes `:101-271`). The router, the OpenAPI document (with an API version separate from the document schema version) and a docs page are generated from that table (`OpenAPIDocument.swift`; `DocsPage.swift`; `apps/mac/Sources/LocalAPIController.swift:225`). An AsyncAPI document describes the socket. Paths are prefixed `/v1`.
- **Event bus** with nine topics (show, timers, audio, transport, outputs, library, scheduler, timecode, fires) (`APIEventBus.swift:4-13`). Events are buffered newest-first and bounded: 16 per topic on the bus, 64 per socket; slow clients lose old events and never block the producer (`APIEventBus.swift:35`; `APIWebSocketHandler.swift:33`). The socket also accepts route commands with the same scope checks. Document schemas come from one JSON schema with a code generator (`packages/schema/documents.json`, `packages/schema/codegen.mjs`).

**Recommendation for GSS.** The MxU shape matches ADR 0006 almost exactly, which is a good sign the ADR was right. Specific choices for GSS:
- Generate routes from the **command catalogue** (section 3), not a second hand-written table: one source for UI, API, OpenAPI and docs. A test fails if a command lacks a route.
- Events carry a **sequence number** per topic and the socket offers "give me the current state" on (re)connect, so a client that dropped events resynchronises instead of drifting. Bounded buffers as in ADR 0006 rule 4. Version the API separately from the file formats; publish the OpenAPI and AsyncAPI documents with each release; JSON Schemas of the file formats are already promised by ADR 0005.

### 4.2 Several Macs (follow mode)

**How MxU does it.** Bonjour discovery, code pairing, then the follower uses the same API: it gets a snapshot with a timestamp, reconstructs media and audio positions from elapsed time, replays fired actions, downloads missing media by hash and verifies it (`apps/mac/Packages/LocalAPI/…/FollowMode.swift:57-59`, `:67-114`, `:151-188`, `:229-232`; `apps/mac/Sources/FollowFileCopy.swift:48-93`). One-way, leader is the authority, follower restricted to view routes.

**Recommendation for GSS.** The right model for a backup or second-room Mac: one leader, followers mirror, **built on the public API** (ADR 0006 rule 2), with content moved by hash. It needs no new data model. Following is optional per computer: a prompter Mac can run at its own pace (decision D4).

### 4.3 MIDI, timecode, NDI, Syphon, DeckLink, streaming

**How MxU does it.** CoreMIDI input with a designated timecode source and MIDI output as a slide action (`apps/mac/Sources/MIDIInService.swift:17-49`, `:97-103`; `apps/mac/Sources/ActionRouter.swift:590`, `:620`). A timecode follower with explicit states (no input, locking, locked, freewheel, stopped), a short freewheel window and a drift tolerance before resync (`…/Timeline/TimecodeFollow.swift:5`, `:35`, `:50`, `:78`, `:270`, `:286`). NDI and DeckLink out of process (1.1); Syphon in process; streaming to RTMP, SRT and HLS through a third-party library. No single output abstraction; one controller per output kind (`apps/mac/Sources/OutputPicture.swift:8-150`).

**Recommendation for GSS.** Keep these in Phases 4-5. When they arrive: one **output sink interface** owned by GSS (frames in, status out, supervision per 1.1) that NDI, Syphon and SDI implement; the timecode follower as an explicit state machine with tests for dropout and freewheel. Streaming should stay out of scope: OBS and hardware switchers do it better, and our key output already feeds them.

### 4.4 Extensibility for third parties

**How MxU does it.** The API is the extension point. No native Stream Deck, Companion, Planning Center, OBS or mobile integration was found in the app.

**Recommendation for GSS.** ADR 0006 is already better than MxU here (out-of-process extensions, official remote on the public API). Integrations after the API follow the owner's order (O7): Planning Center, OBS, then Global Connect.

| Tool | Best route for GSS | Who builds it |
|---|---|---|
| Planning Center (first) | An out-of-process importer that writes `.plan.json` files using `externalIds` (ADR 0005) | Us |
| OBS (second) | Key output into OBS today; OBS WebSocket actions as macros later | Extension |
| Global Connect (third) | The church management app the project is building, with a plan module; another client of the same API and of campus sync | Us |
| Phone control | A web remote served by the app first, a native app later (O6) | Us, Phase 3 |
| Bitfocus Companion | A Companion module over the local API (the usual path for live production gear) | Community or us, outside the app |
| Stream Deck | Through Companion first; a native Elgato plug-in later only if asked | Same |

Publish a small **extension kit**: the OpenAPI document, an example client, and a fake server for tests, so third parties can build without a running app.

## 5. Local data and the cloud

### 5.1 What MxU actually does

- Documents (presentations, themes and others) are **Automerge files** on disk, one per document (`apps/mac/Packages/PresenterCore/…/Documents/DocumentStore.swift:24`; also in backups, `…/Library/BackupBundle.swift:268-277`).
- Automerge gives them: editor "replicas" with scoped undo/redo and history (`…/Documents/EditorReplica.swift:13`, `:44-56`, `:80`), incremental change encoding since known heads (`apps/mac/Sources/SlideEditorModel.swift:2866`), and subtree revert (`SubtreeRevert.swift`).
- A raw SQLite index in WAL mode sits in the library root, with `entities`, `usage` and `sync_ledger` tables (`…/Library/Library.swift:15`; `…/Library/LibraryIndex.swift:59-102`); a test named `SyncOwedTests` suggests a queue of changes owed to a future sync. Media is content-addressed by SHA-256 in `blobs/`, fonts by hash in `fonts/` (`…/BlobStore.swift:106`).
- **No sync transport, server or cloud was found.** Follow mode copies media blobs, not document changes. So in MxU, Automerge today buys history, undo and a merge-ready format, and an option for sync later, at the cost of a binary format and a vendored Rust-backed dependency.

### 5.2 Where GSS stands

- ADR 0004/0005/0007: JSON files in a user-chosen folder are the only source of truth; deterministic output; stable ids down to sections and lines; a rebuildable SQLite index outside the folder; a change journal (built for songs, `Sources/GSSLibrary/LibraryIndex.swift:43-47`), base copies and tombstones planned; a future protocol with per-item server versions, conditional writes and field-level three-way merge using section and line ids. CRDTs were considered and deferred to the sync ADR. Folder sync (iCloud, Dropbox, Syncthing) is best-effort with conflict copies shown.
- At the time of this research the feature map marked "Cloud sync" out of scope (`docs/feature-map.md:95`), and the roadmap excludes accounts, subscriptions and telemetry that identifies a church (`docs/roadmap.md:92`).

### 5.3 What a church needs

As first stated: a shared song library, services planned from another computer (a planner at home, the operator at church), offline work and sensible conflicts. The owner narrowed the first need to **one library per campus** (decision D1): the computers of one campus (projection, prompter, the pastor's laptop, the band's playback laptop) each hold the data locally and keep the reusable bank of songs, templates and similar items in sync.

### 5.4 Options

| | A. Files + any file-sync tool | B. Files + our own optional sync (ADR 0007's plan, built) | C. CRDT documents (Automerge-style) with optional sync |
|---|---|---|---|
| Source of truth | JSON files | JSON files; a hub or server keeps versions | CRDT document; JSON exported or kept beside it |
| Offline | Yes | Yes | Yes |
| Shared library | Only by sharing a folder; no permissions, no curation | Yes: a library the campus subscribes to, plus the computer's own copy | Yes, with the same server work as B |
| Planning from another computer | Works if both use the same synced folder; conflicts become conflict copies | Yes; plan edits merge per item id; real conflicts shown to the user | Yes; concurrent edits merge automatically |
| Conflict quality | Whole-file conflict copies | Field-level three-way merge with ids; user decides true conflicts | Automatic merge, including concurrent edits to the same text (can produce surprising mixed lyrics) |
| Open formats (ADR 0004) | Kept | Kept | Broken or duplicated: a binary document beside or instead of JSON |
| Dependency and platform | None | Our protocol; a server only if the cloud is added | Large Rust-backed library; must be verified for macOS 13 and x86_64; Global Connect and any web client need the same library |
| Undo/history | Built separately (command model) | Built separately | Comes with the format |
| Cost to build | Done (watching still to build) | Medium: protocol, pairing, later a server | High: format migration, export, server still needed for a shared library |
| Fits "no accounts" | Yes | Yes over the LAN; a cloud needs campus keys or accounts | No, if a cloud is involved |

**Analysis.**
- Songs and themes are edited rarely and mostly by one person; **plans** are where two people touch the same item in the same week. Because every plan item, song section and line already has a stable id, item-level three-way merge (option B) resolves the realistic cases: one person reorders, another changes a key, both edits survive. Character-level CRDT merging of lyric text solves a case churches rarely have and can create text nobody wrote.
- The pattern the brief describes (a complete local store that works alone, plus an optional cloud that exchanges changes) is exactly option B: local-first, the cloud as an addition, never a requirement. It does not need a CRDT.
- A library **shared across several churches** is mostly a *distribution* problem (publish, subscribe, update, "this church changed its copy"), closer to a package registry than to collaborative editing. It can be modelled as a separate read-only library mounted next to the church's own, with "copy to my library". It stays an idea for later (D1).
- Copyright: sharing lyrics across churches redistributes them. Each church's CCLI or equivalent licence covers its own use, not redistribution to other churches. This needs legal advice before any cross-church library ships, whatever the technology.

**Decision (D1-D4):** option B, no CRDT; files stay the source of truth. What ADR 0007 planned and still lacks (folder watching, conflict detection on save, base copies) is built before 1.0. Campus sync comes after the first release, over the LAN first; the cloud is decided later. It gets its own ADR.

### 5.5 How others share data across one campus (D4)

- **MxU Slides:** no accounts and no cloud found. Macs on the LAN pair through Bonjour and a code that mints a revocable token; the follower mirrors live state and fetches missing media by hash. Library content is not synced (section 4.2).
- **ProPresenter Network Link:** machines on one LAN form a group and any of them can take control; only live state travels, matched by position, so every machine must already hold the same content; remote apps connect with IP, port and a password ([Network Link](https://support.renewedvision.com/hc/en-us/articles/4412193892627-Network-Link)). **ProPresenter Cloud** (version 22 and later, replacing Local Sync): syncs a whole workspace (presentations, media, libraries, playlists, themes, stage layouts and more) to every computer signed into the organisation; it needs an account in an organisation and a subscription, includes 50 GB and two editor seats (more are paid), watermarks the output of editors without a seat; shows work offline but sync needs internet ([ProPresenter Cloud](https://renewedvision.com/propresenter/cloud)). Conflict handling is not documented publicly.

**Options for GSS, in the order they could be built:**
1. **Campus link over the LAN, no accounts.** One Mac (normally the projection computer) is the campus hub. Other Macs pair with a short code, keep a full local copy of the library, work offline, and exchange changed items with the hub when they see it, using the ADR 0007 journal and item-level merge. Live follow uses the same pairing and is optional per computer.
2. **Cloud relay with a campus key.** The same protocol through a small, open-source, self-hostable server, so a laptop can sync from home. Identity is a campus key created on the hub, not personal accounts.
3. **Cloud through Global Connect accounts.** Global Connect already knows the church, campus and people. Most convenient for Global's own campuses, but other churches would depend on it.

Recommendation: build 1 first; design the protocol so 2 and 3 are only a different transport and identity, and choose between them after 1 works. Never tie editing to a paid seat or watermark the output.

## 6. Modern intelligence

Deferred by the owner (I1-I4). This section is kept as notes; nothing in it is decided.

### 6.1 What MxU does

No machine learning or language-model features were found (searches for Core ML, Vision, Speech, NaturalLanguage, Translation, Foundation Models and common LLM providers). "Smart" features are deterministic and offline: a slide planner that splits pasted text and moves bracketed text to notes (`apps/mac/Packages/PresenterCore/…/SlidePlanner.swift:524-575`), scripture references detected by pattern (`…/ScriptureReference.swift:31-43`), and golden fixtures for splitting (`packages/make-slides-fixtures/`).

### 6.2 Constraints for GSS

- Minimum macOS 13 and Intel support. Apple's on-device language model (Foundation Models) needs a recent macOS and Apple silicon with Apple Intelligence; the Translation framework needs a newer macOS than 13. Any feature built on them is **unavailable on part of the supported fleet** and must degrade to "not available on this Mac".
- The live path is closed (ADR 0006). Intelligence never runs during Live on the operator's critical path, never blocks a command, and never changes content without the operator accepting it.
- Privacy and copyright: sending lyrics to a cloud model sends licensed text to a third party. Opt-in only, per action, with the destination named; offline by default. Out-of-process by design: intelligence is a natural first **extension** (ADR 0006 layer 3). If it hangs or crashes, the app does not notice.

### 6.3 Candidate features, ranked by value and risk

| Feature | Value | How, offline-first | Risk | Recommendation |
|---|---|---|---|---|
| Song search that tolerates typos, partial lines and accents | High, used every service | FTS5 already strips accents; add prefix and fuzzy matching, then on-device sentence embeddings (NaturalLanguage, available on macOS 13) | Low | First, and mostly not AI |
| Lyric splitting into sections and slides | High | Improve the deterministic splitter with golden fixtures; a model only suggests section labels for pasted lyrics, shown as a proposal | Low | Deterministic first; model suggestions later |
| Bilingual draft translation | Medium-high for Global's churches | On-device translation where available, marked as a machine draft a person must review; never auto-shown live | Medium: quality of sung translations; translating copyrighted lyrics creates a derivative work that needs permission | Only as an editor aid, with a clear "draft" state, after legal review |
| Service builder | Medium | Templates (feature map Phase 2) and Planning Center import cover most of it deterministically | Low | Templates first; AI not needed |
| Setup assistant | Medium | A deterministic display and output wizard with test patterns (section 3) | Low | Wizard, not AI |
| Lyrics following audio, live captions | High for some churches | On-device speech recognition, out of process | High: wrong advance in front of the room | Later, as an extension, never auto-advance by default |

### 6.4 Rules to record (ADR "Optional intelligence", when the topic is reopened)

Off by default; offline-first; out of process; never on the live path; proposals, never silent edits; lyrics never leave the Mac without explicit, per-use consent; every feature has a non-AI path that works on a 2017 Intel Mac on macOS 13.

## Stability risks to address before adding features

Ordered by the damage they can do during a live service. Paths are under `Sources/GSSApp/` unless given in full.

| # | Risk | Evidence in GSS | Proposed fix |
|---|---|---|---|
| R1 | Main-thread file I/O and plan resolution while Live; a slow or evicted iCloud file freezes the operator window and the outputs | `AppState.swift:307`, `:314`, `:348`, `:354`, `:360`, `:393`, `:398`, `:432`, `:466`, `:475` | Move all I/O behind actors; `perform` only mutates memory; preload everything a plan needs before it goes live |
| R2 | Outputs drawn by SwiftUI on the main thread, so any main-thread stall freezes the screens | `AudienceOutput.swift` (SwiftUI output views; no display link) | Measure, then decide the output rendering path (O4) |
| R3 | No compiler protection against data races | `Package.swift:27` (Swift 5 mode); `AppState.swift:129` (no `@MainActor`) | Swift 6 mode per module; `@MainActor` state |
| R4 | A crash loses the live position and unsaved service changes | `AppState.swift:191` (only a dirty flag) | Crash-safe live state and autosave |
| R5 | No logs, breadcrumbs or hitch detection; Sunday failures cannot be diagnosed | No `os.Logger` in `Sources/`; errors dropped at `AppState.swift:310`, `:361`, `:467` | Logger categories, breadcrumb journal, main-thread watchdog, Report a Problem |
| R6 | Files changed by sync tools are overwritten silently; changes made outside the app are not seen until reopen | No FSEvents in `Sources/` (ADR 0007 rule 2 unbuilt); atomic writes without a hash check | Folder watching and conflict check on save |
| R7 | Importers without limits; listing decodes every file | `SongFile.swift:9`; `Sources/GSSCore/Import/OpenLyricsImporter.swift:43`; `Sources/GSSLibrary/Library.swift:106`; search with `limit: 10_000` at `AppState.swift:760` | Input limits; list from the index, not by decoding files |
| R8 | No backups; a bad save or a deleted folder loses the library | No backup code | Scheduled local backups with restore |
| R9 | No signed app bundle; cannot ship, request permissions or run helpers properly | No `Info.plist` or entitlements; `docs/roadmap.md:23` open | Signed, notarized pipeline |
| R10 | No soak, no x86_64 or Thread Sanitizer run in CI | `.github/workflows/ci.yml` | Soak mode on the Intel Mac; TSan and x86_64 in CI |

Not verified and worth a focused look: whether the output reads an immutable snapshot (ADR 0006 rule 2) or live view state, and what the helpers in `AppState.swift:492-875` do off the main thread.

## Proposed ADRs

The two written first are numbered; the others are numbered when written.

| ADR | Title | Decision in one line |
|---|---|---|
| 0012 | Concurrency policy | Swift 6 language mode in every target, UI state on the main actor, no file, network or decode work on the main thread, real-time threads never wait on a lock (R1, R3). |
| 0013 | Recovery | Every go-live persists a crash-safe live position, editors autosave with a conflict check, the library is backed up on a schedule, and missing media is relinked by content hash (R4, R6, R8). |
| — | Output rendering path | The outputs draw from immutable, pre-prepared frames on a path the main thread cannot stall; the technology is chosen after measuring on the Intel Mac (O4). |
| — | Process isolation and supervision | Closed SDKs, untrusted-file conversion and extensions run in supervised helper processes that the app can restart and resend state to, and the output never waits for them. |
| — | Live-safety diagnostics | Local logs, a breadcrumb journal and a main-thread watchdog are always on; nothing leaves the Mac unless the operator sends a report. |
| 0007 amendment (form to be decided when written) | Library storage and sync | Folder watching and conflict detection on save are required for 1.0. |
| — | Untrusted input | Every importer has size, count and depth limits, refuses XML entities and unsafe archive paths, and runs out of process when it parses third-party binaries. |
| — | Local API v1: security and events | Off by default, loopback by default with LAN as an explicit opt-in (O5), scoped revocable tokens, no tokens in URLs, an origin allow-list, bounded event buffers with sequence numbers, routes generated from the command catalogue. |
| — | Campus sync | Files stay the source of truth; our own optional sync with item-level three-way merge, a campus hub over the LAN first, cloud transport and identity decided later (D1-D4). |
| — | Command catalogue and operator lock | Every operator action is a named, localised command with a shortcut, a scope and a lock flag, and the UI, shortcuts, API and remote all use it (O8). |
| — | Optional intelligence | Deferred (I1-I4); the rules in 6.4 are the starting point. |

ADR 0006 does not need to change: MxU's design confirms it. The output rendering path and process isolation ADRs make its performance rules 1-2 and extension rule 4 enforceable.

## Roadmap after the decisions

### Before the first public release (end of Phase 1)

A **reliability gate** inside Phase 1 (accepted, O2), after the work in flight and before new Phase 1 features. No new Phase 1 scope until the gate is done; features already built stay and must pass it (O3).

1. Concurrency migration and I/O off the main thread (R1, R3).
2. Output path measured on the 2017 Intel Mac and fixed if it shares the main thread (R2).
3. Logging, breadcrumbs, main-thread watchdog, Report a Problem (R5).
4. Crash-safe live position, autosave with conflict check, folder watching (R4, R6).
5. Importer limits; listing from the index (R7).
6. Scheduled backups with restore; missing-media relink by hash (R8).
7. Signed and notarized bundle with updates; not sandboxed, hardened runtime (R9, O9).
8. Soak mode passing two hours with zero dropped frames on the Intel Mac; TSan and x86_64 in CI (R10).

Then the remaining Phase 1 features, each entering only with its tests, its failure behaviour and its recovery written down. The **locked operator mode** is in the first release (O8), built on the command catalogue with shortcuts, together with the first-run display setup.

### After the first release

- Phase 2 as planned (bilingual lyrics first: the formats already carry it).
- Phase 3: local API (loopback by default, LAN opt-in), a **web remote** served by the app first and a native phone app later (O6), Companion module, extension kit.
- Integrations after the API, in order: **Planning Center, OBS, Global Connect** (O7).
- Phase 4: output sink interface and supervised NDI/SDI helpers; MIDI and timecode follower.
- **Campus library sync** (D1-D4): the bank of songs, templates and similar items kept on every computer of a campus, over the LAN first; the cloud is decided later. Live follow on the public API, optional per computer.
- Ideas for later: sync across several churches, after legal advice on redistributing lyrics; AI, once the system is solid (I1-I4).

## Owner decisions (2026-11-25)

Recorded in English; the owner answered in Spanish, and quotes are faithful translations of the owner's words.

| # | Question | Decision |
|---|---|---|
| D1 | Shared song library, and for whom? | Per campus, not across churches. The owner: "The idea is to have a library, but per campus, not so much at a global level." Example: the Barquisimeto campus runs a projection computer and a prompter computer, sometimes a laptop for the pastor's presentations and one for the band's live playback; all hold their data locally and stay in sync through the network or the cloud. A library shared across several churches is an idea for later. |
| D2 | Data model: A, B or C? | Option B: files stay the source of truth, plus our own optional sync with item-level three-way merge; no CRDT. |
| D3 | Sync before or after the first release? | After the first release. |
| D4 | Accounts, server and who runs it? | LAN first. The owner: "local first, the cloud is decided later." Live follow is optional per computer: "that the prompter computer can go at its own pace." Sync covers the reusable bank, not only live state: "sync the libraries of songs, templates and those things that are kept as a bank to reuse." Options in 5.5. |
| O1 | What does a "first sellable version" mean for an MIT project; should the licence change? | Keep MIT; ADR 0003 unchanged. See below. |
| O2 | Reliability gate before new Phase 1 features? | Accepted. |
| O3 | Move any Phase 1 feature out? | No new Phase 1 scope until the gate is done; features already built stay and must pass the gate. |
| O4 | Output rendering path? | Measure the current outputs on the 2017 Intel Mac first, then decide. |
| O5 | API on the LAN? | Loopback by default; LAN access is a separate opt-in. |
| O6 | Phone control? | Web remote first, native app later. |
| O7 | First integrations after the API? | Planning Center, OBS, then Global Connect. |
| O8 | Locked operator mode? | In the first release, built on the command catalogue. The owner: "Whatever is most recommended." |
| O9 | App Sandbox? | Not sandboxed for 1.0; hardened runtime; helpers isolated. |
| I1-I4 | Which intelligence features, cloud models, Apple-silicon-only, legal advice on translations? | Deferred. The owner: "We leave the AI topic for later, once we have a good system." |

### O1: licence

- Under the Open Source Definition, a licence that forbids selling or business use is not open source; a no-sale project is "source-available" ([OSD](https://opensource.org/osd)).
- PolyForm Shield (MxU's licence) does not forbid selling, only competing with the licensor. PolyForm Noncommercial 1.0.0 is the closest no-sale fit: charitable organisations may use and fork it ([PolyForm Noncommercial](https://polyformproject.org/licenses/noncommercial/1.0.0)), but it would exclude production companies using GSS at paid events, deter contributors who avoid non-OSI projects, and void the broadcast SDK reasoning in ADR 0003.
- AGPL-3.0 keeps every fork open but allows selling. MIT allows selling and protects only the name and logo (`TRADEMARKS.md`).
- Decision: keep MIT. Published versions stay MIT for whoever received them; any later change needs legal advice and a new ADR that supersedes ADR 0003.

## Appendix: where MxU is weaker than GSS (do not copy)

- No localisation; English strings hard-coded across the app. Minimal accessibility; dark theme forced by default. macOS 14 and Apple silicon only.
- API listens on every interface, wildcard CORS, tokens in query strings, non-constant-time comparison, unauthenticated docs that trust the `Host` header. No zip bomb limits, no fuzzing.
- No CI configuration in the repository; no in-app updater found.
- Binary document format (Automerge) instead of open, documented files.
