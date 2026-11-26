# Live measurement

The live measurement finds out how long the main thread stalls while a service runs. The output windows are SwiftUI views on the main thread, and several operator actions still read and write files there ([ADR 0012](adr/0012-concurrency-policy.md)), so a main-thread stall freezes the operator window and the screens together. These results decide how the outputs are drawn. They are taken on the Intel test machine, the 2017 MacBook Pro ([ADR 0002](adr/0002-minimum-macos-13.md)).

The app runs a service the way an operator would, using only the commands the interface uses. It switches to Live, opens the most recent service, shows the outputs, then shows every slide of every item at a fixed pace and clears the screens with Clear All. It repeats this for a number of rounds. It times every command on the main thread. Meanwhile a watchdog on a background thread checks the main thread every 50 ms and records each time it takes longer than 100 ms to answer, with the action that was running.

It is a developer mode, started with a launch argument. Its console output is in English only. Without the argument the app behaves as usual.

## Build and run

On the Intel 2017 MacBook Pro, from the repository root:

```bash
swift build -c release --product GlobalServiceStudio

# Run the built app with the measurement (3 rounds, one slide every 1.5 s)
"$(swift build -c release --show-bin-path)/GlobalServiceStudio" --measure-live ~/Desktop/gss-live.json

# Or build and run in one step
swift run -c release GlobalServiceStudio --measure-live ~/Desktop/gss-live.json --rounds 5 --pace 1
```

| Option | Meaning |
|---|---|
| `--measure-live <file>` | Run the measurement and write the JSON report to the file |
| `--rounds N` | Times the whole service is shown, 3 by default |
| `--pace SECONDS` | Time between actions, 1.5 by default |

A run takes about rounds × slides × pace seconds: 3 rounds of a 100-slide service take about 8 minutes. At the end the app prints a summary, writes the report and quits. It exits with code 1 and a message when it cannot start, for example without a library or without a dated service. Do not use the app until it quits.

## Which library

The measurement uses the library chosen in Settings (⌘,) when you run the app the same way, and the service changed most recently that has a date. Templates are skipped.

- Use a realistic library. Your own library is best; it stays on the Mac.
- Use a service like a real one, with songs and presentations. Every item should be found in the library: a missing item opens an alert over the window on every round.
- If you keep the library in iCloud Drive, run it once with the library there and once with it in a local folder, and note which is which.

## For a fair measurement

- Plug in the power adapter and close other apps.
- Connect the second display. The audience output opens on the display the Output menu would choose. With one display no output is shown, and the run says so. The key and stage outputs are shown only when a display is already chosen for them, which needs the Output menu before the run starts, so a normal run shows the audience output only.
- Keep the windows visible. macOS stops drawing hidden windows.
- Run it twice and keep the second result. The first run after a build also loads files into the disk cache.

## Reading the results

The summary looks like this (the numbers are invented):

```text
machine: MacBookPro14,3, Intel(R) Core(TM) i7-7820HQ CPU @ 2.90GHz, 16 GB, macOS 13.7.0, x86_64
library: 412 songs, 18 presentations, 52 plans
run: 3 rounds of 96 slides at 1.5 s, outputs: audience

action                     count   avg ms   p95 ms   max ms  stalls  worst stall ms
setMode(live)                  1     38.2     38.2     38.2       1           160.4
openLaunchService              3    210.5    240.1    240.1       3           380.2
...
```

| Column | Meaning | Good result |
|---|---|---|
| `action` | The command: `nextSlide` within an item, `nextSlide.newItem` when it enters the next item, `clearAll`, `openLaunchService`, `selectOutputScreen` and `showAudienceOutput` | |
| `count` | Times it ran | |
| `avg ms`, `p95 ms`, `max ms` | Time the command took on the main thread: average, 95th percentile, longest | Ideally under one frame (16.7 ms at 60 Hz) for slide changes and Clear All |
| `stalls` | Stalls over 100 ms that began while this action was the latest one | 0 for slide changes and Clear All |
| `worst stall ms` | The longest of those stalls | |

A command's time covers only the command. The drawing it causes comes after, so a slow redraw shows as a stall of that action, not in its time. A stall carries the latest action until the next one starts.

The goal is no stall over 100 ms on the actions that put something on air: `nextSlide`, `nextSlide.newItem` and `clearAll`. Opening a service and switching to Live are expected to be slower today, because they read files on the main thread.

The JSON report has the same summary, every stall with its time since the start, its length and its action, and the totals. Its keys are sorted, so two reports can be compared line by line.

## Results

Fill in one table per machine, macOS version and library place.

Machine: MacBook Pro 2017, Intel ____, ____ GPU, macOS ____. Displays: ____. Library: ____ songs, ____ presentations, local / iCloud Drive. Service: ____ items, ____ slides.

| Action | Count | Avg ms | p95 ms | Max ms | Stalls | Worst stall ms | Notes |
|---|---|---|---|---|---|---|---|
| setMode(live) | | | | | | | |
| openLaunchService | | | | | | | |
| selectOutputScreen | | | | | | | |
| showAudienceOutput | | | | | | | |
| nextSlide | | | | | | | |
| nextSlide.newItem | | | | | | | |
| clearAll | | | | | | | |

Total stalls: ____. Longest stall: ____ ms during ____.
