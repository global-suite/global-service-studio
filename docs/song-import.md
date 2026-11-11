# Song import strategy

How songs get into Global Service Studio without an integration with a commercial song catalogue.

## The constraint

Most commercial presentation software can search CCLI SongSelect and import lyrics from inside the app. That depends on a partner agreement. As of November 2026, CCLI has retired its SongSelect partner API program and is not accepting new integrators, so this project cannot offer that integration, and may never be able to.

The plan below does not depend on that changing.

## What the app does instead

1. **Make typing and pasting fast.** Paste a whole song and the editor splits it into slides at blank lines, recognizes labels such as "Verse 1" and "Chorus", and builds the groups. For most volunteers this is already how songs get entered.
2. **Import open formats.**
   - [OpenLyrics](https://docs.openlyrics.org/), an open XML standard for worship songs. Also supported for export.
   - ChordPro.
   - OpenSong.
   - Plain text.
3. **Import files the church already has the right to use.** A church with its own SongSelect subscription can download lyric files from the SongSelect website and import those files. The license belongs to the church; the app only reads a file the user provides.
4. **Import from other presentation software**, so an existing library is not retyped.
5. **Support license compliance.** A place for the church's CCLI license number, song credits shown on the first or last slide, and an exportable log of which songs were used and when, for manual reporting.
6. **Offer public domain hymns** as an optional download.

## What the app will not do

- Bundle or distribute copyrighted lyrics.
- Scrape lyrics from websites or from services that do not permit it.
- Ask for or store a user's credentials for a third-party service in order to work around a missing integration.

## Rules for contributors

- Tests and sample data use invented placeholder text or public domain hymns, never copyrighted lyrics.
- An importer reads a documented or openly specified format. If a format is undocumented, the pull request explains how it was understood and confirms that no proprietary code or documentation was copied.
- Importers live in `GSSLibrary`, one per format, each with tests built from small sample files.

## If a partner program opens

An integration would be added as an optional module in `GSSIntegrations`, after an ADR. Nothing above would be removed: file import stays the baseline that always works.
