# 0003. MIT license with a separate trademark policy

- Status: Accepted
- Date: 2026-11-11

## Context

The project is open source from its first commit and expects outside contributors. It will also link proprietary SDKs for broadcast output, such as NDI and Blackmagic DeckLink, whose licenses do not allow redistribution under copyleft terms. The project name should keep identifying the official builds, even though anyone may fork the code.

## Decision

- The code is licensed under the **MIT License**. Copyright is held by Isaac Páez.
- The name and logo are governed by a separate [Trademark Policy](../../TRADEMARKS.md): forks must use their own name and branding.
- Contributions are accepted under the same MIT license. There is no contributor license agreement.

## Alternatives considered

- **GPL-3.0.** Would keep every fork open. Rejected: it conflicts with linking the proprietary broadcast SDKs, and it deters some contributors and integrators.
- **MPL-2.0 or Apache-2.0.** Both workable. MIT was chosen for its simplicity and because it is what contributors in this ecosystem expect.

## Consequences

- Anyone may use, modify, sell or close a fork of the code. Only the name and logo are protected.
- Proprietary SDKs can be linked. They are still never committed to the repository: each is an optional integration that the builder downloads under its own license.
- Third-party content keeps its own license. Song lyrics, Bible translations, fonts and media are not covered by the project's MIT license and must not be committed unless they are public domain or openly licensed.
