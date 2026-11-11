<!--
  Every pull request must link an issue that has the `status:approved` label.
  CI rejects pull requests without a linked approved issue, without exactly one
  `type:*` label, or over 400 changed lines without `size:exception`.
  See CONTRIBUTING.md for the full workflow.
-->

## Linked Issue

Closes #

<!-- Replace with the approved issue number, e.g. "Closes #42". Fixes and Resolves also work. -->

## PR Type

Check exactly one, and make sure the pull request has the matching label.

- [ ] `type:bug` — Bug fix
- [ ] `type:feature` — New feature or enhancement
- [ ] `type:docs` — Documentation only
- [ ] `type:refactor` — Code change with no change in behavior
- [ ] `type:chore` — Build, CI, tooling, tests
- [ ] `type:breaking-change` — Changes existing behavior or a file format

## Summary

<!-- One to three bullet points: what this pull request does and why. -->

-

## Changes

| File / Area | Change |
|---|---|
| `path/to/file` | What changed |

## Test Plan

- [ ] `swift test` passes
- [ ] Tested on Apple silicon
- [ ] Tested on Intel
- [ ] Manually tested the affected behavior

<!-- Describe manual steps, displays or outputs used, and anything you could not test. -->

## AI Assistance

Check exactly one. See [AI_POLICY.md](https://github.com/global-suite/global-service-studio/blob/main/AI_POLICY.md).

- [ ] **None** — No material AI assistance was used.
- [ ] **Material assistance used** — Fill in the fields below.

**Tool:**

**Scope:**

**Verification:**

## Contributor Checklist

- [ ] The linked issue has `status:approved`
- [ ] The pull request has exactly one `type:*` label (a maintainer adds it if you cannot add labels)
- [ ] Commits and the pull request title follow [Conventional Commits](https://www.conventionalcommits.org/)
- [ ] Within 400 changed lines (additions plus deletions), or a maintainer granted `size:exception`
- [ ] Every new or changed user-facing string is localized in English and Spanish
- [ ] Docs are updated if behavior changed
- [ ] No `Co-Authored-By` or similar trailers for AI tools
