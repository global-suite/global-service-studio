# Architecture Decision Records

An ADR records one significant decision: what was decided, why, and what it costs. Read them to understand why the project is built the way it is.

| # | Decision | Status |
|---|---|---|
| [0001](0001-native-swift-stack.md) | Build a native app with Swift, AppKit, SwiftUI and Metal | Accepted |
| [0002](0002-minimum-macos-13.md) | Support macOS 13 Ventura and later, on Apple silicon and Intel | Accepted |
| [0003](0003-mit-license-and-trademark-policy.md) | MIT license with a separate trademark policy | Accepted |
| [0004](0004-open-file-formats.md) | Store user content in open, versioned files | Accepted |
| [0005](0005-file-format-design.md) | Design of the song, theme, presentation and service plan formats | Accepted |
| [0006](0006-extensibility-and-live-performance.md) | Extensibility without cost to the live output | Accepted |
| [0007](0007-library-storage-and-sync.md) | Library storage, search index and the path to sync | Accepted |

## Adding one

A decision needs an ADR when it is expensive to reverse: a dependency, a file format, a platform requirement, a module boundary.

1. Open an issue and get it approved, like any other change.
2. Copy the structure below into `docs/adr/NNNN-short-title.md`, using the next number.
3. Add it to the table above.

An accepted ADR is not edited to change its decision. Write a new ADR that supersedes it, and mark the old one `Superseded by NNNN`.

```markdown
# NNNN. Title

- Status: Proposed | Accepted | Superseded by NNNN
- Date: YYYY-MM-DD

## Context
What forces the decision.

## Decision
What we will do.

## Alternatives considered
What else was on the table, and why not.

## Consequences
What gets easier, what gets harder, what we accept.
```
