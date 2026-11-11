# Instructions for coding agents

Global Service Studio is a native macOS presentation app for churches and live services, written in Swift.

## Skills

Before writing code, load the skill that matches your task and follow it.

| Skill | Load when | Path |
|---|---|---|
| `gss-issue-creation` | Creating or triaging an issue | [skills/gss-issue-creation/SKILL.md](skills/gss-issue-creation/SKILL.md) |
| `gss-branch-pr` | Creating a branch, commits or a pull request | [skills/gss-branch-pr/SKILL.md](skills/gss-branch-pr/SKILL.md) |
| `gss-core-rules` | Changing anything under `Sources/GSSCore` | [skills/gss-core-rules/SKILL.md](skills/gss-core-rules/SKILL.md) |
| `gss-file-formats` | Adding or changing a file format | [skills/gss-file-formats/SKILL.md](skills/gss-file-formats/SKILL.md) |
| `gss-localization` | Adding or changing user-facing strings | [skills/gss-localization/SKILL.md](skills/gss-localization/SKILL.md) |
| `gss-render-path` | Touching rendering, outputs, the local API or extensions | [skills/gss-render-path/SKILL.md](skills/gss-render-path/SKILL.md) |

To add or change a skill, follow [docs/skill-style-guide.md](docs/skill-style-guide.md).

## Rules that are easy to break

- **Deployment target is macOS 13.** Do not use newer APIs (`@Observable`, `Observation`, SwiftData, and so on) without `if #available` and a working fallback.
- **Universal binary.** Code must build and run on both `arm64` and `x86_64`.
- **`GSSCore` is portable.** No AppKit, SwiftUI, Metal, AVFoundation or other Apple UI or media imports in it.
- **Every user-facing string is localized** in English (base) and Spanish. See `docs/localization.md`.
- **Nothing but the render engine runs on the render path**, and extensions never run inside the app's process. See `docs/adr/0006-extensibility-and-live-performance.md`.
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
node .github/scripts/check-skills-index.mjs   # after adding, renaming or removing a skill
```

`swift test` needs full Xcode. If it fails with `no such module 'XCTest'`, run it as `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`.

## Where things are

| Path | Contents |
|---|---|
| `Sources/GSSCore` | Portable data model and file formats |
| `Tests/` | Unit tests |
| `docs/architecture.md` | Modules and the render engine |
| `docs/adr/` | Architecture decision records |
| `docs/CODEBASE-GUIDE.md` | Mental model and where each kind of change goes |
| `docs/roadmap.md` | Phases and current focus |
| `docs/community-roadmap.md` | How to find work that is ready to be picked up |
| `docs/skill-style-guide.md` | How skills are written |
| `skills/` | Skills for coding agents, indexed above |
| `design/` | Design system (`design/system.md`) and self-contained HTML mockups; use its tokens when building interface |
