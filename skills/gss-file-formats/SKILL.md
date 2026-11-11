---
name: gss-file-formats
description: "Trigger: file format, song, theme, presentation, plan, JSON, envelope, migration, format version. Add or change a Global Service Studio file format without breaking saved files."
license: MIT
metadata:
  author: global-suite
  version: "1.0"
---

## Activation Contract

Load this skill, with `gss-core-rules`, before adding or changing a file format, its fields or its validation.

## Hard Rules

- One item per file; start it with the envelope `format`, `version`, `id` and open it with `Envelope.open`.
- Preserve unknown fields at every level: read objects with `JSONObjectReader`, keep `reader.unknown` in `unknown`, write it back with `JSONValue.object(_:unknown:)`.
- Conform every part to `JSONRepresentable` and pass the key path to nested reads.
- Model open string values as `OpenStringValue` so unknown values survive.
- Keep absent optional fields absent when writing.
- Write deterministic output with `canonicalData()`: saving an unchanged item gives identical bytes.
- `decode(from:)` validates; `encoded()` does not. Throw `FormatError` with the key path of the failing field.
- Reference other items by identifier and media with `MediaReference` (library-relative path plus `sha256`).
- Keep `externalIds` and `extensions` namespaced; never interpret `extensions`.
- Use BCP 47 language tags.

## Decision Gates

| Change | Version and label |
|---|---|
| New optional field | Same `version`; no migration |
| An older reader would misread the file | Bump `version`, add a migration, test files from the previous version, `type:breaking-change` |

## Execution Steps

1. Read ADR 0005 and an existing format, for example `Sources/GSSCore/Song`.
2. Add tests, following `Tests/GSSCoreTests/SongFormatTests.swift`:
   - the example decodes, and encodes back byte for byte;
   - unknown fields and unknown open values survive at every level;
   - absent optional fields stay absent;
   - a newer `version` and a wrong `format` are rejected;
   - a missing required field reports its key path;
   - one test per validation rule, asserting the key path.
3. Use invented text in examples.
4. Run `swift test`.

## Output Contract

Report the format and version, the fields changed, whether a migration was needed and why, and the test results.

## References

- [ADR 0004](../../docs/adr/0004-open-file-formats.md): open, versioned files
- [ADR 0005](../../docs/adr/0005-file-format-design.md): shared rules and examples
- [Format foundation](../../Sources/GSSCore/Format/FormatFields.swift)
- [Shared values](../../Sources/GSSCore/Format/SharedValues.swift)
- [Song format tests](../../Tests/GSSCoreTests/SongFormatTests.swift)
