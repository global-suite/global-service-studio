# Contributing to Global Service Studio

Thank you for wanting to help. Please read this guide fully before you start: the workflow is strict so that the project stays organized and reviews stay fast.

- [Issue-first workflow](#issue-first-workflow)
- [Looking for something to work on?](#looking-for-something-to-work-on)
- [AI-assisted contributions](#ai-assisted-contributions)
- [Labels](#labels)
- [Development setup](#development-setup)
- [Branches](#branches)
- [Commits](#commits)
- [Pull requests](#pull-requests)
- [Code rules](#code-rules)
- [Roles and permissions](#roles-and-permissions)
- [Notes for maintainers](#notes-for-maintainers)

## Issue-first workflow

**No pull request without an approved issue.**

1. **Open an issue** with the [Bug Report](https://github.com/global-suite/global-service-studio/issues/new?template=bug_report.yml) or [Feature Request](https://github.com/global-suite/global-service-studio/issues/new?template=feature_request.yml) form. Blank issues are disabled.
2. **Wait for approval.** New issues get `status:needs-review`. Work may begin only after a maintainer adds `status:approved`.
3. **Comment on the issue** to say you are taking it, so nobody duplicates the work.
4. **Open a pull request** that links the approved issue.

CI rejects pull requests that are not linked to an approved issue.

Questions and ideas that are not yet concrete go to [Discussions](https://github.com/global-suite/global-service-studio/discussions).

## Looking for something to work on?

Start at the [roadmap](docs/roadmap.md). Issues labelled [`up-for-grabs`](https://github.com/global-suite/global-service-studio/issues?q=is%3Aissue+is%3Aopen+label%3Aup-for-grabs) are scoped, approved and unclaimed: comment that you are taking one and go.

An issue labelled `status:needs-design` or `status:needs-info` is waiting on a decision or on missing information. Discuss it first; code written before the decision usually gets thrown away.

## AI-assisted contributions

AI assistance is allowed, but you must understand and own everything you submit. Before opening a pull request:

- Confirm the change matches the approved issue scope.
- Inspect every changed line.
- Remove invented, unverifiable or unrelated output.
- Run the tests and report what actually happened.
- Be ready to explain the design and its tradeoffs.
- Disclose material AI assistance in the pull request.

The full rules are in the [AI policy](AI_POLICY.md).

## Labels

### Type (issues and pull requests)

Pull requests need **exactly one**.

| Label | Meaning |
|---|---|
| `type:bug` | Bug fix |
| `type:feature` | New feature or enhancement |
| `type:docs` | Documentation only |
| `type:refactor` | Code change with no change in behavior |
| `type:chore` | Build, CI, tooling, tests |
| `type:breaking-change` | Changes existing behavior or a file format |

### Status (issues)

| Label | Meaning |
|---|---|
| `status:needs-review` | Newly opened, waiting for a maintainer |
| `status:approved` | Approved for implementation; a pull request may be opened |
| `status:needs-design` | Waiting on an architecture or product decision |
| `status:needs-info` | Waiting on information from the reporter |

### Priority

| Label | Meaning |
|---|---|
| `priority:high` | Important, affects many users or blocks a service |
| `priority:medium` | Normal priority |
| `priority:low` | Nice to have |

### Other

| Label | Meaning |
|---|---|
| `up-for-grabs` | Approved, scoped and unclaimed |
| `good first issue` | A good starting point for a new contributor |
| `help wanted` | Maintainers would like help here |
| `size:exception` | Maintainer-approved exception to the pull request size budget |
| `duplicate`, `wontfix` | Resolution |

Only maintainers add or remove `status:approved` and `size:exception`.

## Development setup

You need a Mac with **Xcode 26 or later**. The app targets **macOS 13 Ventura** and must build for both Apple silicon and Intel.

```bash
git clone https://github.com/global-suite/global-service-studio.git
cd global-service-studio
swift build
swift test
```

If `swift test` reports `no such module 'XCTest'`, your command line points at the standalone Command Line Tools instead of Xcode. Fix it once with `sudo xcode-select -s /Applications/Xcode.app`.

## Branches

Never commit to `main`. Create a branch named `type/description`, lowercase:

```
^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert)\/[a-z0-9._-]+$
```

Examples: `feat/song-arrangements`, `fix/output-wrong-display`, `docs/song-import`.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): description
```

Examples:

```
feat(library): add song arrangements
fix(render): keep the video layer under the slide layer
docs(roadmap): mark stage display as in progress
```

Do not add `Co-Authored-By` or similar trailers for AI tools.

## Pull requests

- Link the approved issue with `Closes #N` (or `Fixes #N`, `Resolves #N`). The full issue URL also works: `Closes https://github.com/global-suite/global-service-studio/issues/N`. References inside HTML comments are ignored. Markdown code is not parsed, so a reference inside a code block or inline code also counts: write the closing keyword only for the issue you mean to close.
- The pull request needs exactly one `type:*` label. If you cannot add labels, tick the type in the pull request template and a maintainer adds the label; the check re-runs when the label is added.
- If the issue is approved after you opened the pull request, `Linked approved issue` does not refresh by itself. Edit the pull request description (any change works) or ask a maintainer to re-run the check.
- Stay within **400 changed lines** (additions plus deletions). Split larger work into a chain of small pull requests, each one useful on its own. A maintainer can grant `size:exception` when splitting makes no sense, for example for generated files.
- Keep tests and documentation in the same pull request as the behavior they cover.
- Fill in the pull request template completely, including the test plan and the AI assistance section.
- All checks must pass. Pull requests are squash-merged, so the pull request title must also be a valid Conventional Commit.

## Code rules

- **Swift only**, formatted consistently with the surrounding code.
- **`GSSCore` stays portable.** It holds the data model and file formats and must not import AppKit, SwiftUI, Metal, AVFoundation or any other Apple UI or media framework. See the [architecture](docs/architecture.md).
- **No API newer than macOS 13** without an `if #available` check and a working fallback.
- **Every user-facing string is localized** in English and Spanish. See [localization](docs/localization.md).
- **Behavior changes come with tests.**
- **File formats are a contract.** A change to a saved format needs a version bump, a migration and `type:breaking-change`.
- **No copyrighted content.** Do not commit song lyrics, Bible translations, fonts or media unless they are in the public domain or openly licensed, and say which license applies.

## Roles and permissions

| Role | Who | Can do |
|---|---|---|
| Contributor | Anyone | Open issues, comment, open pull requests from a fork |
| Triage | Trusted contributors | Label and close issues; `status:approved` and `size:exception` stay with maintainers by rule, not protected labels |
| Maintainer | Invited by the owner | Approve issues, review and merge pull requests, grant size exceptions |
| Owner | Isaac Páez | Releases, repository settings, roles, final decisions |

Roles are granted by invitation, based on sustained, careful contributions.

## Notes for maintainers

- **Required checks are matched by name.** A pull request that adds a workflow with a job of the same name could report a passing check without the real policy running. Review any pull request that touches `.github/` with care, and never approve workflow runs from a first-time contributor without reading the workflow changes.
- **Maintainer-only labels are a rule, not a protection.** GitHub's Triage role can technically add any label, including `status:approved` and `size:exception`. The team follows the rule, and Triage is granted with that in mind.
- **Test the policy checks.** After changing `.github/workflows/pr-policy.yml`, run `node .github/scripts/test-pr-policy.mjs`. CI runs it too.

## Code of Conduct

By participating you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
