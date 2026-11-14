# The library folder

A library is a folder the user chooses, laid out as decided in [ADR 0007](adr/0007-library-storage-and-sync.md). The `GSSLibrary` module reads and writes it.

```
<Library>/
  library.json
  Songs/  Themes/  Presentations/  Plans/  Media/
```

## `library.json`

```json
{
  "format": "gss.library",
  "id": "3d0c6a52-5b8e-4f0a-9c1d-7e2b4a6f8c10",
  "name": "Placeholder Library",
  "version": 1
}
```

- `format`, `version` and `id` are the envelope of [ADR 0005](adr/0005-file-format-design.md). The `id` never changes and names the library's search index.
- `name` is the folder name when the library is created.
- Opening a missing or empty folder creates `library.json` and the five folders. A `library.json` of another format or a newer version, or a non-empty folder without one, is refused and nothing in it is changed.

## Song files

- A song is saved atomically to `Songs/<slug>-<first 8 hex digits of its id>.song.json`, such as `morning-light-6f1c2b9e.song.json`.
- The slug is the title in lowercase ASCII, accents removed, words joined by `-`, at most 60 characters, or `song` when nothing is left.
- Identity is the `id` inside the file: a song that already has a file is saved to that file, whatever its name.
- Listing reads every `*.song.json` in `Songs/`; a file that cannot be read is reported with its error, never skipped.
- A plan is saved the same way to `Plans/<slug>-<first 8 hex digits of its id>.plan.json`, such as `sunday-gathering-d51b0c3e.plan.json`, with the slug made from its title, or `plan` when nothing is left ([ADR 0009](adr/0009-service-plan-format.md)).
