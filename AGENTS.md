# Instructions for coding agents

Global Service Studio is a native macOS presentation app for churches and live services, written in Swift.

## Rules that are easy to break

- **Deployment target is macOS 13.** Do not use newer APIs (`@Observable`, `Observation`, SwiftData, and so on) without `if #available` and a working fallback.
- **Universal binary.** Code must build and run on both `arm64` and `x86_64`.
- **`GSSCore` is portable.** No AppKit, SwiftUI, Metal, AVFoundation or other Apple UI or media imports in it.
- **Every user-facing string is localized** in English (base) and Spanish. See `docs/localization.md`.
- **Saved file formats are a contract.** Changing one needs a version bump and a migration.
- **No copyrighted lyrics, Bible text, fonts or media** in the repository or in tests. Use invented placeholder text.

## Workflow

- Read `CONTRIBUTING.md`. Work is issue-first: a pull request must link an issue labelled `status:approved`.
- Branches: `type/description`. Commits and pull request titles: Conventional Commits.
- Keep pull requests within 400 changed lines; split larger work.
- Do not add `Co-Authored-By` or similar trailers for AI tools. Disclose AI assistance in the pull request, per `AI_POLICY.md`.
- Repository-facing text (code, comments, docs, commits, issues) is in English.

## Commands

```bash
swift build
swift test
node .github/scripts/test-pr-policy.mjs   # after changing .github/workflows/pr-policy.yml
```

`swift test` needs full Xcode. If it fails with `no such module 'XCTest'`, run it as `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.

## Where things are

| Path | Contents |
|---|---|
| `Sources/GSSCore` | Portable data model and file formats |
| `Tests/` | Unit tests |
| `docs/architecture.md` | Modules and the render engine |
| `docs/adr/` | Architecture decision records |
| `docs/roadmap.md` | Phases and current focus |
