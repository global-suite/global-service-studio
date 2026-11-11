---
name: gss-branch-pr
description: "Trigger: branch, commit, pull request, PR, split a large change, size budget. Prepare branches, commits and pull requests that pass the Global Service Studio policy checks."
license: MIT
metadata:
  author: global-suite
  version: "1.0"
---

## Activation Contract

Load this skill before creating a branch, writing a commit message or opening or editing a pull request.

## Hard Rules

- Never commit to `main`. Name the branch `^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert)\/[a-z0-9._-]+$`.
- Write commits as Conventional Commits: `type(scope): description`.
- Write the pull request title as a Conventional Commit too; pull requests are squash-merged.
- Link an issue that has `status:approved` with `Closes #N`, `Fixes #N` or `Resolves #N`, or the full issue URL. References inside HTML comments are ignored; code blocks are not, so write the keyword only for the issue you mean to close.
- Give the pull request exactly one label of `type:bug`, `type:feature`, `type:docs`, `type:refactor`, `type:chore`, `type:breaking-change`. If you cannot add labels, tick the type in the template.
- Stay within 400 changed lines (additions plus deletions) unless a maintainer granted `size:exception`.
- Keep tests and documentation in the same pull request as the behavior they cover.
- Fill in every template section, including Test Plan and AI Assistance.
- Disclose material AI assistance: tool, scope and verification you performed.
- Never add `Co-Authored-By`, `Reviewed-by`, `Tested-by` or `Signed-off-by` trailers for AI tools. `Assisted-by` is optional.

## Decision Gates

| Situation | Action |
|---|---|
| Change over 400 lines | Split into a chain of small pull requests, each useful on its own |
| A pull request depends on an unmerged one | Build its branch on the earlier branch; open it after the earlier one merges |
| `main` moved after your branch was pushed | Merge `main` into the branch; do not rebase, and never force-push a shared branch |
| Split makes no sense, for example generated files | Ask a maintainer for `size:exception` |
| Issue approved after the pull request was opened | Edit the description, or ask a maintainer to re-run the check |
| Changes a saved format or existing behavior | `type:breaking-change` |

## Execution Steps

1. Confirm the linked issue has `status:approved`.
2. Create the branch from `main` with a valid name.
3. Commit work with Conventional Commit messages.
4. Count changed lines: `git diff --numstat main...HEAD`.
5. Run `swift build` and `swift test` and record what actually happened.
6. Open the pull request with the template filled in and the matching `type:*` label.

## Output Contract

Report the branch, commits, changed-line total, linked issue, type label, test results and the pull request URL.

## References

- [CONTRIBUTING.md](../../CONTRIBUTING.md): branches, commits, pull requests
- [Pull request template](../../.github/PULL_REQUEST_TEMPLATE.md)
- [AI_POLICY.md](../../AI_POLICY.md)
- [PR policy workflow](../../.github/workflows/pr-policy.yml)
