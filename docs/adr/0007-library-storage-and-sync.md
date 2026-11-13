# 0007. Library storage, search index and the path to sync

- Status: Accepted
- Date: 2026-11-13

## Context

The app cannot save songs yet: a song opened from a file is lost when the app closes. Before the library is built, its storage and the path to cloud sync must be decided, because both are expensive to change once churches have libraries.

[ADR 0004](0004-open-file-formats.md) already decides that JSON files are the source of truth and that a SQLite index is a rebuildable cache. [ADR 0005](0005-file-format-design.md) gives every item a stable `id`, deterministic output, and `externalIds`. Neither decides which index technology to use, where the index lives, how it stays consistent with files that other tools can change, or how sync will work later.

The forces:

- **Search is the main way operators find songs during a service.** It must be instant, match as the operator types, and ignore accents: "corazon" finds "corazón".
- **Files change outside the app.** Users edit them in other tools, copy libraries between campuses, and keep them in iCloud Drive, Dropbox or Syncthing.
- **Sync is wanted later, not now.** Whatever is built now must not need rewriting when it arrives, and must not depend on a service that can disappear.
- **The slowest supported machine is a 2017 Intel Mac on macOS 13** ([ADR 0002](0002-minimum-macos-13.md)), and no closed dependency may be required ([ADR 0006](0006-extensibility-and-live-performance.md)).

## Decision

### The library folder

JSON files in a folder the user chooses remain the only source of truth. ADR 0004 is unchanged.

```
<Library>/
  library.json        library UUID and layout version
  Songs/
  Themes/
  Presentations/
  Plans/
  Media/
```

File names are a readable slug plus a short id, such as `morning-light-6f1c2b9e.song.json`. The name is for people; identity is always the `id` inside the file.

### The index

- **SQLite through [GRDB.swift](https://github.com/groue/GRDB.swift)** (MIT license), using the SQLite that ships with macOS.
- **Full-text search with FTS5** over titles, lyrics in every language, authors, tags and CCLI number. The tokenizer is `unicode61 remove_diacritics 2`, which removes diacritics from all Latin characters ([SQLite FTS5](https://www.sqlite.org/fts5.html)). Prefix indexes make search-as-you-type fast. Results are ranked with `bm25`, with the title weighted above other fields.
- **Stored in** `~/Library/Application Support/GlobalServiceStudio/Index/<libraryId>.sqlite`, never inside the library folder, so sync tools never copy a database that is being written.
- **Rebuilt, not migrated.** When the index schema changes, the index is deleted and rebuilt from the files.
- The index and everything in this record live in the `GSSLibrary` module. `GSSCore` stays free of SQLite.

### Keeping the index consistent with the files

1. **At launch, reconcile.** Compare each file's size and modification time with the index; only when they differ, compare a content hash. Unchanged files are not read.
2. **While running, watch with FSEvents.** When FSEvents reports that events were dropped or that a full rescan is needed, rescan the library.
3. **Write atomically.** The app writes to a temporary file and replaces the original, so no reader sees half a file.
4. **Ignore the app's own writes** by recognising their content hash when FSEvents reports them.
5. **Renames and moves keep identity.** A file that reappears under another name with the same `id` is the same item.
6. **Show problems instead of hiding them.** Two files with the same `id`, and conflict copies made by sync tools, are listed for the user to resolve.
7. **Download iCloud placeholders before reading.** A file that iCloud has evicted is downloaded first, never read as empty or skipped as deleted.

### Prepared for sync now, built later

Built from the start, because it is cheap now and expensive to add later:

- **A local change journal** in the index database: for each item, its `id`, content hash, base server version, a dirty flag, and a deleted-at time.
- **Base copies** of each item as last synced, kept outside the library folder, so a later merge has a common ancestor.
- **Tombstones for deletes**, so a delete is propagated instead of the item being restored by another device.

The intended shape of the future protocol:

- Per-item server versions and a cursor-based change feed.
- Conditional writes that carry the base version; a stale write is rejected, not applied.
- Field-level three-way merge, using section and line ids. When both sides changed the same field, the user decides.
- Media synced separately, addressed by content hash.
- Global Connect is another client of the same API, matching items through `externalIds`.

A separate ADR defines the protocol before any sync is built.

### Folder sync

A library kept in iCloud Drive, Dropbox or Syncthing is supported on a best-effort basis. Those tools resolve conflicts by making conflict copies, which the app detects and shows (rule 6 above). It does not merge them.

### Performance targets

Measured on the Intel test machine with a generated library of 5,000 songs of invented text:

| Operation | Target |
|---|---|
| Warm launch reconcile | under 0.2 s |
| Search query | under 10 ms |
| Full index rebuild | a few seconds |

## Alternatives considered

- **Core Data.** A mature object graph, but its store is an opaque database that wants to be the source of truth, contradicting ADR 0004; full-text and accent-insensitive search would still need SQLite underneath.
- **SwiftData.** Requires macOS 14 ([Apple](https://developer.apple.com/documentation/swiftdata)), above the macOS 13 deployment target, and has the same source-of-truth problem as Core Data.
- **Realm.** Its own database format, and its sync service, Atlas Device Sync, reached end of life on September 30, 2025 ([MongoDB](https://www.mongodb.com/docs/device-sdks-deprecation/)): the risk of building on a vendor's sync.
- **CloudKit or `NSPersistentCloudKitContainer`.** Apple-only, so Global Connect, a web or Windows client could not use it, and it gives little control over conflict resolution.
- **CRDTs such as Automerge, for now.** They merge without a server, but add a document format beside the JSON files and a large dependency. Section and line ids already give field-level merge; CRDTs can be reconsidered by the sync ADR.
- **Hosted sync engines (PowerSync, ElectricSQL, Turso).** They sync a database, not files, and tie the project to a vendor's service and server stack, against ADR 0006.
- **The SQLite C API directly, or SQLite.swift.** The C API means writing and maintaining connection handling, statement caching and concurrency by hand. SQLite.swift is a lighter query layer; GRDB already provides the database pooling, migrations and FTS5 support the index needs.

## Consequences

- Songs always work offline. Sync, when it comes, is an addition to the files, not a replacement for them.
- Losing or corrupting the index costs only a rebuild, never data.
- GRDB is a third-party dependency with one main maintainer. It is MIT licensed and confined to `GSSLibrary`; if it is abandoned, the project can fork it or replace it with the C API without touching the file formats.
- GRDB 7 requires Swift 6.1 or Xcode 16.3 or later ([README](https://github.com/groue/GRDB.swift)). Contributors need that toolchain, and CI must keep it: the `macos-15` runner currently defaults to Xcode 16.4.
- FSEvents and iCloud have edge cases: dropped events, delayed modification times, evicted files, conflict copies with odd names. Each needs a test with a generated library, and the launch reconcile is the safety net when live watching misses something.
- Users who keep a library in a sync folder and later turn on GSS sync could have two systems moving the same files. The sync ADR must detect this and guide the user to one of them.
- The change journal and base copies are kept before sync exists. They cost some disk space and code that nothing uses yet.
