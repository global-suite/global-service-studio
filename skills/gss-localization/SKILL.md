---
name: gss-localization
description: "Trigger: user-facing string, UI text, translation, Spanish, localization, Localizable.strings, lproj. Localize Global Service Studio strings in English and Spanish."
license: MIT
metadata:
  author: global-suite
  version: "1.1"
---

## Activation Contract

Load this skill before adding or changing any text the user sees.

## Hard Rules

- Hard-code no user-facing string; every one goes through the `Localizable.strings` files of its module, in `Resources/en.lproj` and `Resources/es.lproj`.
- Use no String Catalog (`.xcstrings`): `swift build` does not compile them.
- Add English (base) and Spanish in the same pull request.
- Use a full sentence as the source text, with a comment saying where the string appears.
- Never build a sentence by joining fragments; use format placeholders.
- Use plural variations, not `if count == 1`.
- Format dates, times and numbers with the system formatters.
- Leave room for Spanish text 20 to 30 percent longer; layouts must not clip or overlap.
- Use the glossary translation when the term is in it.
- Write neutral Latin American Spanish with informal `tú`, and Apple's Spanish terms for standard interface items.
- Put no user-facing text in `GSSCore`: return a typed error and let the interface localize it.

## Decision Gates

| Situation | Action |
|---|---|
| You cannot write the Spanish | Say so in the pull request; a maintainer supplies it before merging |
| A term churches keep in English | Keep it only if Spanish would confuse operators, and add it to the glossary |
| A new agreed translation | Add it to the glossary |

## Execution Steps

1. Find the module's `Localizable.strings` files in `en.lproj` and `es.lproj`.
2. Add or change the entry with its comment in both files, with the same key.
3. Check the glossary for every interface term.
4. Check the layout with the Spanish text.

## Output Contract

Report each string added or changed with its English and Spanish text, glossary changes, and anything left for a maintainer to translate.

## References

- [docs/localization.md](../../docs/localization.md): rules, Spanish style, glossary
