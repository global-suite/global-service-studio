# Skill style guide

A skill is a runtime instruction contract for a coding agent, not documentation for people. It tells the agent when to load it, which rules it must not break, how to decide, what to do and what to return. Skills live in `skills/<name>/SKILL.md` and are listed in [AGENTS.md](../AGENTS.md).

## Frontmatter

Every skill starts with this frontmatter, all fields required:

```yaml
---
name: gss-example
description: "Trigger: words an agent or contributor would use. What the skill does."
license: MIT
metadata:
  author: global-suite
  version: "1.0"
---
```

- `name` equals the folder name and starts with `gss-`.
- `description` is one quoted line, starts with `Trigger:` and is at most 250 characters.

## Sections

Use these sections, in this order:

1. **Activation Contract**: the situations that load the skill.
2. **Hard Rules**: constraints the agent must not break.
3. **Decision Gates**: a short table for the choices that change what to do.
4. **Execution Steps**: the ordered workflow.
5. **Output Contract**: what the agent reports when it is done.
6. **References**: relative links to repository files.

## Budget

- The body targets 180 to 450 tokens. The hard maximum is 1000 tokens.
- A skill stays within 60 lines. Move detail into the repository file it comes from and link to it.

## Writing rules

- Write imperative instructions: "Check", "Run", "Report".
- Write one rule per line.
- Link to repository files instead of restating them at length.
- Every rule comes from a repository file: [CONTRIBUTING.md](../CONTRIBUTING.md), [AI_POLICY.md](../AI_POLICY.md), a decision record or the code. If a rule is not written down anywhere, propose it in an issue first; do not add it to a skill.
- Write in English, like everything in the repository.
- Do not add history, motivation or generic advice the agent cannot act on.

## Adding or changing a skill

1. Open an issue and wait for `status:approved`, as for any other change.
2. Follow this guide.
3. Update the skills table in [AGENTS.md](../AGENTS.md) in the same pull request.
4. When you change an existing skill, bump `metadata.version`.
5. When a rule changes in its source file, update the skills that cite it in the same pull request.

## Credit

The structure of this guide and of the skills follows the skill style guide of [Gentleman-Programming/gentle-ai](https://github.com/Gentleman-Programming/gentle-ai). The text is written for this repository.
