# 0013. Recovery after crashes, conflicts and missing files

- Status: Accepted
- Date: 2026-11-25

## Context

A failure during a service is seen by the whole room. The app can crash, the Mac can lose power, a sync tool can change a file while the operator edits it, and a background video can be missing on Sunday morning. The owner accepted a reliability gate inside Phase 1: a feature is ready only when it recovers from its failures. This record covers the risks that lose work or the live position (R4, R6 and R8 of the reliability study in `docs/research/`).

What exists today:

- **Atomic writes.** Songs, plans, presentations, imported slide images and the library manifest are written to a temporary file and moved into place (`Sources/GSSLibrary/Library.swift:56`, `:76`; `Sources/GSSLibrary/LibraryPlans.swift:67`; `Sources/GSSLibrary/LibraryPresentations.swift:33`, `:77`), as [ADR 0007](0007-library-storage-and-sync.md) rule 3 decided.
- **A rebuildable index.** An index that fails its checks is deleted and rebuilt (`Sources/GSSLibrary/LibraryIndex.swift:39-40`), and the change journal with a content hash per song exists (`:43`).
- **Problems are listed.** Unreadable files are reported, and items of a plan that cannot be resolved are shown in an alert when the service opens (`Sources/GSSApp/AppState.swift:479-483`, [ADR 0009](0009-service-plan-format.md)).

What is missing:

- **No autosave.** The service only carries a dirty flag (`Sources/GSSApp/AppState.swift:191`) and is written when the operator saves (`:396-399`). A crash loses every unsaved change.
- **No crash detection and no resume.** At launch the app opens the most recently changed plan with nothing on air (`Sources/GSSApp/AppState.swift:392-395`); where the service was is lost.
- **Silent overwrites.** A save replaces the file without checking whether it changed on disk since it was read, so an edit made by a sync tool or another program is lost without a trace.
- **No folder watching.** ADR 0007 rule 2 decided FSEvents, but nothing in `Sources/` watches the library yet; changes made outside the app are seen only after reopening.
- **No backups.** A bad save, a faulty tool or a deleted folder loses library content.
- **No missing-media flow.** Media is already referenced by library-relative path and `sha256` ([ADR 0005](0005-file-format-design.md), `Sources/GSSCore/Format/SharedValues.swift:14-15`), so it can be found by content, but nothing does it. A theme font that is not installed silently becomes the system font (`Sources/GSSApp/OutputTheme.swift:74-75`).

## Decision

### 1. The live position survives a crash

- **Every go-live and every clear records where the service is:** the plan's `id` and file, the item, the slide, and what each output layer shows (`OutputLayer`), including the media of the media layer and the position of a full-screen video.
- **The record is written off the main thread, atomically, and never delays the output** ([ADR 0006](0006-extensibility-and-live-performance.md) performance rules 1-3). When go-lives come faster than writes, only the latest is written.
- **It lives outside the library folder**, in `~/Library/Application Support/GlobalServiceStudio/Recovery/`, beside the index of ADR 0007, so no sync tool copies it to another computer.
- **An unclean exit is detected by a marker** written at launch and removed on a normal quit. A marker found at launch means the last run ended in a crash, a force quit or a power loss.
- **After an unclean exit the app offers to resume the service** where it stopped. One action reopens the plan and restores every output. Declining opens the app as usual.
- **Resuming never shows stale content.** The plan is read from disk and resolved again before anything goes on air, and media is prepared first. What no longer resolves (a deleted item, a slide that no longer exists, missing media) stays off air, and the operator is told what could not be restored. A full-screen video is restored paused at its recorded position, never playing on its own.

### 2. Autosave with a conflict check

- **The open service and every editor save automatically** a short moment after the last edit, and at once when the operator leaves the item, closes the window or quits. Save stays as a command that writes immediately.
- **Writes stay atomic** and use the library's existing save for each kind of item.
- **Before writing, the file on disk is compared with what was loaded.** The app keeps the content hash of each file it read or wrote. If the file on disk has a different hash, or is gone, the app never overwrites it: it writes its own version as a conflict copy beside it and shows both, as ADR 0007 rule 6 lists two files with the same `id`. Autosave of that item stops until the operator resolves it.
- **An item that does not validate is not written to the library.** Its draft is kept in the recovery folder and the editor shows why it cannot be saved.
- **Autosave never changes what is on air.** Edits to the live plan apply from the next go-live.

### 3. Folder watching is required for the first release

ADR 0007 rules 2 and 4 are built before the first public release, not after it. An item changed on disk that has no unsaved edits in the app is reloaded; one that does becomes a conflict, as above. A change to the live plan never changes the slide on air.

### 4. Scheduled local backups

- **What:** the JSON files of the library folder and `library.json`. Media is excluded: it is large, and it is referenced by content hash, so it can be found again (section 5).
- **Where:** `~/Library/Application Support/GlobalServiceStudio/Backups/<libraryId>/`, outside the library folder, so a deleted or corrupted folder does not take its backups with it.
- **When:** once a day the app is used, at low priority and off the main thread. A fixed number of backups is kept (a setting) and older ones are removed.
- **Before any migration** of a file format or of the library layout, a backup is taken, whatever the schedule.
- **Verified:** each backup is written under a temporary name, records the hash of every file and is renamed only when complete. A backup whose files do not match is reported and is not offered as a restore point.
- **Restore:** a whole backup, or a single item from any backup. A restore first backs up what it replaces, so it can be undone.

### 5. Missing media and fonts

- **Missing media is marked** on every slide, item and editor that uses it, and listed when a plan opens, like a missing song today.
- **Locate:** the operator chooses a folder; the app hashes its files off the main thread and relinks each missing reference whose `sha256` matches, whatever the file is called. A match is copied into the library to its original path, so no item needs to change. If that path holds another file, the match gets a new name and the items that use it are updated through the normal save.
- **On air,** a missing media cue never shows an error image and never blocks the slide: the words go live and the cue shows nothing.
- **A missing font falls back visibly.** The fallback of `OutputTheme.swift` stays, and every theme and slide that uses a font that is not installed is listed with the font's name.

### 6. Nothing leaves the Mac

Recovery data, live position, drafts and backups stay on the Mac and are never sent anywhere. Logs, breadcrumbs and reporting a problem are diagnostics, decided in a separate ADR.

### 7. Each mechanism is tested by causing its failure

Tests use generated libraries with invented text:

- The process is killed during a save: the file holds the old or the new content, never part of either.
- The process is killed after a go-live: the next launch offers to resume at that slide, and resuming after the plan changed on disk shows nothing stale.
- A file is changed on disk while an edit waits for autosave: both versions survive and the conflict is shown.
- Watching reports dropped events: the library is rescanned.
- Media is deleted, then located in a folder where it has another name: it is relinked by hash.
- A backup is corrupted: it is reported, and the other backups still restore.

## Alternatives considered

- **Rely on sync tools and Time Machine.** Not every church Mac has either, and the backup disk is often not connected. A sync tool copies a bad save or a deletion to every computer, so it is not a backup. Neither knows where a service was when the app crashed.
- **`NSDocument` autosave and versions.** It assumes one document per window and one file per document. A library is a folder of items edited from one window, and a service resolves songs and presentations from other files. Its versions live in a per-volume store that is not available on every volume a library can live on, such as network shares, and it has no notion of live state.
- **Keep unsaved edits aside until the operator saves.** Safer against bad edits, but the library on disk would lag behind what the operator sees, other tools and computers would read an old plan, and there would be two truths to reconcile after a crash.
- **A journal of every change, replayed after a crash.** It also gives history and fine-grained undo, but it is a second format beside the JSON files and much more to build and test. It can grow out of the ADR 0007 change journal when sync is built.

## Consequences

- A crash during a service becomes an incident instead of a disaster: one action puts the service back where it was.
- More disk use: daily backups of the JSON files, the live position and drafts. Media is not copied, so backups stay small next to the library.
- More writes: autosave writes after short pauses instead of on demand. Writes stay atomic and off the main thread.
- Checking the hash and then writing leaves a short window in which another program can still change the file; watching narrows it, it does not close it. A sync ADR can add coordinated writes.
- The conflict view, the resume offer, the restore window and the missing-media marks need design work in `design/` before they are built.
- A false unclean exit, such as the app stopped by a debugger, only shows an offer the operator can decline.
- Backups on the same disk do not protect against losing the disk. Time Machine or another copy is still recommended.
- Every new string (the resume offer, conflicts, restore, missing media and fonts) is localized in English and Spanish, as `docs/localization.md` requires.
