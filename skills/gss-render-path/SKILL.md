---
name: gss-render-path
description: "Trigger: render engine, output, display, frame, video, local API, remote, events, extension, plug-in, integration. Keep the live output safe while extending Global Service Studio."
license: MIT
metadata:
  author: global-suite
  version: "1.0"
---

## Activation Contract

Load this skill before touching rendering, outputs, the local API, events, extensions or optional integrations.

## Hard Rules

- Run only the render engine on the render path: no file access, network, API handling, extension call or interface work on a render thread.
- The output reads an immutable snapshot and never waits; other parts change state by submitting commands.
- Apply a command that changes the output on the next frame.
- Prepare slow work, such as decoding media or laying out text, before the item goes live.
- Deliver events asynchronously and bounded; a slow or disconnected client loses events and never slows the app.
- Run extensions out of process; they talk to the app only through the API.
- Require no closed dependency; put a closed SDK in an optional module behind an interface the project owns.
- Make every interface feature reachable through the API once the API exists; until then, build features as commands in the model layer.
- The official remote uses the public API, with no private shortcuts.
- Treat the API as a contract: a breaking change follows the file format rule.

## Decision Gates

| Change | Action |
|---|---|
| Touches the render path | State its effect on frame time on the Intel test machine |
| Needs a closed SDK | Optional module behind a project-owned interface |
| A tool wants to draw into the output | Deliver it as a source the engine composites |

## Execution Steps

1. Read ADR 0006 and the render engine section of the architecture.
2. Identify which thread or process each new piece of work runs on.
3. Move anything slow off the render path and before going live.
4. Measure on the Intel test machine when the render path changes.

## Output Contract

Report what runs where, the frame-time effect measured (or that it was not measured and why), and any new API surface.

## References

- [ADR 0006](../../docs/adr/0006-extensibility-and-live-performance.md): extension layers, rules, performance rules
- [ADR 0002](../../docs/adr/0002-minimum-macos-13.md): the Intel test machine
- [docs/architecture.md](../../docs/architecture.md): output model and render engine
