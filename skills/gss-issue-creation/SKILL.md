---
name: gss-issue-creation
description: "Trigger: new issue, bug report, feature request, triage, approve issue. Create or triage Global Service Studio issues with the issue forms and status labels."
license: MIT
metadata:
  author: global-suite
  version: "1.0"
---

## Activation Contract

Load this skill before creating, editing, labelling or triaging an issue.

## Hard Rules

- Use the Bug Report or Feature Request issue form; blank issues are disabled.
- Search existing issues, open and closed, before creating one; do not open a duplicate.
- Apply only the labels the form declares: its `type:*` label and `status:needs-review`.
- Never add `status:approved` or `size:exception` yourself. Only a maintainer adds them, and an agent does so only when a maintainer explicitly tells it to.
- Do not start implementation until the issue has `status:approved`.
- Include no sensitive data: passwords, tokens, private church or member information, copyrighted lyrics or media.
- Write the issue in English.

## Decision Gates

| Situation | Action |
|---|---|
| Something does not work as expected | Bug Report form |
| A new feature or an improvement, including docs | Feature Request form |
| A question or an idea that is not yet concrete | Discussions, not an issue |
| A matching issue exists | Comment on it instead |
| Issue has `status:needs-design` or `status:needs-info` | Discuss first; write no code |

## Execution Steps

1. Search: `gh issue list -R global-suite/global-service-studio --state all --search "<words>"`.
2. Pick the form from the table and fill in every required field.
3. Tick the preflight checkboxes only when they are true.
4. Create the issue and confirm it has `status:needs-review`.
5. To take an approved issue, comment on it that you are taking it.

## Output Contract

Report the issue number and URL, the form used, its labels, and the duplicate search you ran.

## References

- [CONTRIBUTING.md](../../CONTRIBUTING.md): issue-first workflow, labels, roles
- [Bug Report form](../../.github/ISSUE_TEMPLATE/bug_report.yml)
- [Feature Request form](../../.github/ISSUE_TEMPLATE/feature_request.yml)
- [Issue template config](../../.github/ISSUE_TEMPLATE/config.yml)
