# 0006. Extensibility without cost to the live output

- Status: Accepted
- Date: 2026-11-11

## Context

Two goals pull on the architecture from the start.

**Extensibility.** The owner and contributors should be able to build their own tools on top of Global Service Studio: integrations with planning systems, lyric sync with a playback session, importers, control surfaces, things nobody has thought of yet. The project should also never be limited by closed third-party software it cannot replace.

**Live performance.** The app runs services, events and concerts. A dropped frame, a stall or a crash is seen by the whole room. Performance is judged on the slowest supported machine, an Intel Mac from 2017 ([ADR 0002](0002-minimum-macos-13.md)).

Extensibility is usually where live software loses reliability: a plug-in blocks the main thread, or a faulty one takes the application down. Both goals are cheap to respect from the first feature and expensive to add later.

## Decision

### Three extension layers

Each layer is more powerful than the one before and is built in this order.

1. **Open files.** Every item is a documented, versioned file ([ADR 0005](0005-file-format-design.md)). Any tool can read, create and change songs, themes, presentations and plans. Tools keep their own data in `extensions` and link items to other systems with `externalIds`.
2. **A local API with events.** The app exposes what it can do over the local network: load a plan, go to a slide or a section, clear a layer, send a message. It also publishes events when its state changes. Sections, slides and items are addressed by their stable identifiers.
3. **Out-of-process extensions.** Tools that add importers, outputs or panels run as separate processes and talk to the app through the API.

### Rules

1. **Everything the interface can do, the API can do.** A feature is not finished until it is reachable through the API. This applies once the API exists; until then, features are built as commands in the model layer so that exposing them is mechanical.
2. **The official remote uses the public API**, with no private shortcuts. Third-party tools get the same power as the project's own.
3. **No closed dependency is required.** The app builds and runs using only the system frameworks and the project's own code. A closed SDK, such as a broadcast output, is an optional module behind an interface the project owns, and can be replaced without touching the rest.
4. **Extensions never run inside the app's process.** A faulty extension must not be able to stop the output.
5. **The API is a contract.** It is versioned, and a breaking change follows the same rule as a file format change.

### Performance rules

These keep everything above away from the output.

1. **The render path is closed.** Only the render engine runs on it. No file access, no network, no API handling, no extension call and no interface work happens on a render thread.
2. **The output never waits.** The render engine reads an immutable snapshot of what to show. The interface, the API and extensions change state by submitting commands; the engine picks up the result at the next frame. If any of them stalls, the output keeps showing the last valid state.
3. **Going live is immediate.** A command that changes the output is applied on the next frame. Anything slow, such as decoding media or laying out text, is prepared before the item goes live.
4. **Events are best effort.** Event delivery to API clients is asynchronous and bounded. A slow or disconnected client loses events; it never slows the app.
5. **Performance is measured, on the slow machine.** Changes to the render path state their effect on frame time on the Intel test machine. A frame budget and automated measurements are added with the render engine.

## Alternatives considered

- **In-process plug-ins loaded as dynamic libraries.** The most powerful option and the usual one for creative software. Rejected: one faulty plug-in stops the output, and loading unsigned code conflicts with notarized distribution.
- **An embedded scripting language.** Safer than native plug-ins, but still inside the process, and a second platform to design, document and secure. Can be reconsidered later as an extension that runs out of process.
- **No extension story; fork to customize.** Rejected: it pushes every church with a special need to maintain a fork.

## Consequences

- Extensibility does not cost frames: extensions and API clients are outside the render path by construction, not by discipline.
- An extension cannot draw into the output directly. Extensions that produce visuals deliver them as a source the engine composites, such as a video input or a shared texture, at the cost of one extra hop.
- A command sent over the API reaches the screen one frame later than a keypress at most; this is not perceptible.
- The local API becomes a security surface. It is off until the operator enables it, and it needs pairing and permissions before it ships.
- Building features as commands first is extra structure early on. It is also what makes undo, the remote and automation possible.
- Apple's platform remains a dependency that cannot be removed: macOS, Xcode and code signing. `GSSCore` staying free of Apple-only frameworks limits how far that dependency reaches.
