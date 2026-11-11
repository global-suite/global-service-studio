# 0004. Store user content in open, versioned files

- Status: Accepted
- Date: 2026-11-11

## Context

A church's song library and service plans are years of volunteer work. They should outlive any one computer, be easy to back up and share between campuses, and never be locked inside an application. The project also has no integration with a commercial song catalogue (see [song import strategy](../song-import.md)), so importing and exporting files is the main way content moves.

## Decision

- Songs, presentations, playlists and themes are stored as **documented JSON files**, one item per file, in a library folder the user chooses.
- Every file carries a **format version**. The app migrates older versions when it opens them and never silently drops fields it does not understand.
- A **SQLite index** provides fast search. It is a cache: it can always be rebuilt from the files and is never the source of truth.
- Media files are referenced, not embedded.
- The formats are defined in `GSSCore` and documented in `docs/` when they are introduced.

## Alternatives considered

- **A single database as the source of truth.** Simpler queries. Rejected: opaque to the user, hard to merge, and hard to sync with ordinary file tools.
- **A binary or proprietary format.** Smaller and faster. Rejected: it recreates the lock-in this project is meant to avoid.
- **An existing open song format as the native format.** OpenLyrics is a good interchange format, but it does not cover slides, themes, media cues or playlists. It is supported for import and export instead.

## Consequences

- Users can back up, version and sync a library with any file tool.
- Third-party tools can read and write the library.
- A change to a saved format is a breaking change: it needs a version bump, a migration, tests with files from the previous version, and the `type:breaking-change` label.
