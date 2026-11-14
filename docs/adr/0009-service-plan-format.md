# 0009. Service plan format details

- Status: Accepted
- Date: 2026-11-14

## Context

[ADR 0005](0005-file-format-design.md) designed the service plan (`gss.plan`): a title, an optional date, start times, a theme and items of kind `header`, `song`, `presentation`, `media` and `item`. Building version 1 in `GSSCore` needed decisions that ADR 0005 left open.

## Decision

- **Items reference other files by id only.** A song item holds the song's `id`, never its title; a presentation item holds the presentation's `id`. Media is a `MediaReference` (library-relative path and `sha256`), as in themes and presentations.
- **A missing song, arrangement or presentation does not make the plan invalid.** The plan file validates on its own. The library or the app reports a reference it cannot resolve when the plan is opened or used, so a plan stays readable after a song is deleted or before it is synced.
- **Item ids are unique within one plan and never empty.** They are short strings, like section ids in a song.
- **Each kind checks only what it cannot work without:** a song item needs `song`, a presentation item needs `presentation`, a media item needs `media` with a library-relative path. Other fields are optional on every kind. Unknown kinds are kept and not checked.
- **`position` is an open value.** `pre`, `during` and `post` are known; any other value is kept as written, like section and element kinds.
- **`length` is a number of seconds, zero or more.** Fractions are allowed; whole numbers are written as integers.
- **`date` is a calendar day `YYYY-MM-DD`** and a time `start` is a 24-hour `HH:MM`, both without a time zone: they are the local time of the place of worship. A plan without `date` is a template.
- **Items carry `externalIds` and `extensions`,** like the plan, so an integration maps each item to its source.
- **Plans are stored like songs:** one file per plan in `Plans/`, named `<slug>-<first 8 hex digits of its id>.plan.json`, saved atomically. Identity is the `id` inside the file.

## Alternatives considered

- **Reject a plan whose song is missing.** Rejected: one deleted song would make a whole order of service unreadable, and a plan synced before its songs would fail to open.
- **Separate types per item kind.** Rejected for version 1: one item type with optional fields, like presentation elements, keeps unknown kinds and fields with no extra code.
- **Reject unknown positions.** Rejected: a value added by a newer version or another tool must survive being saved.

## Consequences

- The library needs a way to resolve plan references and report the missing ones; that is built with the plan interface.
- The date and times carry no time zone; a church that streams across zones will need a later optional field.
