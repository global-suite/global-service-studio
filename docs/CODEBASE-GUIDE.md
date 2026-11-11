# Codebase guide

This guide helps you find the right place before changing Global Service Studio. It is an index, not a reference: it points to the code and to the documents that decide how the code is written.

## Who this is for

| Reader | Use this guide to |
|---|---|
| New contributor | Build a mental model before touching files |
| Contributor with a task | Find the module that owns a behavior |
| Reviewer | Check that a pull request changes the right layer |
| Coding agent | Know which skill to load; the index is in [AGENTS.md](../AGENTS.md) |

## The 90-second mental model

Global Service Studio is a native macOS app that sends lyrics, slides, images and video to the screens of a live service.

```text
Files in a library folder        songs, themes, presentations (open JSON)
        │  read and written by
        ▼
GSSCore                          the model: what a song, a theme, a slide is
        │  used by
        ▼
The app                          the operator picks what goes live
        │  submits commands, never draws
        ▼
The render engine                composites each output, every frame
        │
        ▼
Outputs                          audience screens, stage display, key output
```

Three ideas explain most decisions:

1. **Content and style are separate.** A song stores sections and lines, with no fonts, colors or slide breaks. A theme decides how lines are split and how they look. One song serves every screen. See [ADR 0005](adr/0005-file-format-design.md).
2. **The output never waits.** Only the render engine runs on the render path. Everything else changes state by submitting commands. See [ADR 0006](adr/0006-extensibility-and-live-performance.md).
3. **Old Macs count.** The app targets macOS 13 on Apple silicon and Intel, and performance is judged on a 2017 Mac. See [ADR 0002](adr/0002-minimum-macos-13.md).

## What exists today

Only `GSSCore` exists. The other modules in [architecture.md](architecture.md) are added as the [roadmap](roadmap.md) reaches them.

| Path | Contents |
|---|---|
| `Sources/GSSCore/OutputLayer.swift` | The fixed order in which layers are composited |
| `Sources/GSSCore/Format/` | Shared by every file format: JSON values, canonical output, unknown-field preservation, the envelope, errors, shared values |
| `Sources/GSSCore/Song/` | The song format: model, reading and writing, validation |
| `Sources/GSSCore/Theme/` | The theme format |
| `Sources/GSSCore/Presentation/` | The presentation format |
| `Tests/GSSCoreTests/` | One test file per source area; format tests and validation tests are separate |
| `.github/` | Issue forms, the pull request template, CI and the policy checks |
| `skills/` | Task-oriented instructions for coding agents |
| `docs/adr/` | Why things are the way they are |

## Where a change goes

| You want to | Start here | Read first |
|---|---|---|
| Add a field to a format | The format's folder in `Sources/GSSCore` | [gss-file-formats](../skills/gss-file-formats/SKILL.md) |
| Add a new file format | `Sources/GSSCore/Format/` for what is shared, a new folder for the rest | [ADR 0005](adr/0005-file-format-design.md) |
| Change anything in `GSSCore` | `Sources/GSSCore` | [gss-core-rules](../skills/gss-core-rules/SKILL.md) |
| Add or change text the user sees | The interface module, never `GSSCore` | [localization.md](localization.md) |
| Touch rendering, outputs or the API | The render engine or remote module, once they exist | [ADR 0006](adr/0006-extensibility-and-live-performance.md) |
| Change a policy check | `.github/workflows/pr-policy.yml` and its test | [CONTRIBUTING.md](../CONTRIBUTING.md#notes-for-maintainers) |
| Record a decision that is expensive to reverse | `docs/adr/` | [adr/README.md](adr/README.md) |

## Commands

```bash
swift build                                  # build
swift build --arch x86_64                    # check the Intel build
swift test                                   # run the tests
node .github/scripts/test-pr-policy.mjs      # after changing the policy workflow
node .github/scripts/check-skills-index.mjs  # after adding, renaming or removing a skill
```

If `swift test` fails with `no such module 'XCTest'`, see [CONTRIBUTING.md](../CONTRIBUTING.md#development-setup).

## Before you open a pull request

Work is issue-first, and pull requests are small. The full rules are in [CONTRIBUTING.md](../CONTRIBUTING.md); work that is ready to be picked up is in the [community roadmap](community-roadmap.md).
