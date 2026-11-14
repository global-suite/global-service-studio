# Video benchmark

`GSSVideoBench` measures heavy video playback before the media layer relies on it. [ADR 0008](adr/0008-media-layer-key-output-and-video.md) requires 4K H.264 and HEVC at 30 and 60 frames per second on two outputs to be measured on the Intel test machine, the 2017 MacBook Pro ([ADR 0002](adr/0002-minimum-macos-13.md)). The supported limits in the documentation come from these results.

It plays video the way the app will: AVPlayer decodes each file once with the hardware decoder, `AVPlayerItemVideoOutput` hands out BGRA pixel buffers, `CVMetalTextureCache` turns them into Metal textures without a CPU copy, and every output window draws the same texture at the display refresh. Audio plays through the default output device.

It is a developer tool, separate from the app. Its console output is in English only.

## Build and run

On the Intel 2017 MacBook Pro, from the repository root:

```bash
swift build -c release --product GSSVideoBench

# 1. Generate the test clips (about 1.8 GB; this takes several minutes)
swift run -c release GSSVideoBench make-clips ~/Desktop/gss-clips

# 2. Play every clip on two outputs and print a summary
swift run -c release GSSVideoBench run-all ~/Desktop/gss-clips

# Or play one clip
swift run -c release GSSVideoBench play ~/Desktop/gss-clips/hevc-2160p60.mp4 --outputs 2 --seconds 30 --fullscreen
```

| Command | Options |
|---|---|
| `make-clips <dir>` | `--seconds N`: clip length, 20 by default |
| `play <file>` | `--outputs 1\|2` (1 by default), `--seconds N` (30 by default), `--fullscreen` |
| `run-all <dir>` | `--outputs 1\|2` (2 by default), `--seconds N` (15 by default), `--fullscreen` |

`make-clips` writes eight clips, all invented: a moving gradient with noise, a moving square, the frame number and a 440 Hz tone in AAC.

| Codec | Sizes | Frame rates | Bitrate |
|---|---|---|---|
| H.264 and HEVC | 1920×1080 and 3840×2160 | 30 and 60 | 20 Mbit/s (1080p30) to 80 Mbit/s (2160p60) |

If the Mac cannot encode HEVC, those clips are skipped with a message. You can also copy your own test files into the folder; `run-all` plays every `.mp4`, `.mov` and `.m4v` in it.

For a fair measurement:

- Plug in the power adapter and close other apps.
- Connect the second display when you test two outputs. With `--fullscreen`, each output fills its own screen. With one screen, both windows share it.
- Keep the windows visible. macOS stops drawing hidden windows.
- Open Activity Monitor to watch GPU use and the `VTDecoderXPCService` process, which may do decoding outside the benchmark.

## Reading the results

Each playback skips its first second while the windows open, then prints one row and one JSON line:

```text
file                   out   secs  shown   late dropped  avg ms worst ms  cpu %
hevc-2160p60.mp4         2   15.0    901      0       0   16.67    21.07    5.9
{"avgIntervalMs":16.67,"cpuPercent":5.9,"dropped":0,"file":"hevc-2160p60.mp4",...}
```

| Column | Meaning | Good result |
|---|---|---|
| `shown` | New video frames put on screen | About seconds × frame rate |
| `late` | Display refreshes when a frame was due but none was decoded yet | 0 |
| `dropped` | Video frames skipped entirely | 0 |
| `avg ms` | Average time between new frames | 33.3 at 30 fps, 16.7 at 60 fps |
| `worst ms` | Longest time between new frames | Under twice the average |
| `cpu %` | CPU used by the benchmark process; 100 is one full core | Low enough to leave room for the app |

A clip that plays longer than its length loops by seeking to the start. That seam shows as a few `late` refreshes and a long `worst ms`, so `run-all` stays under the clip length by default.

Collect the JSON lines with `grep '^{'` to compare runs.

## Results

Fill in one table per machine and macOS version. Use two outputs and `run-all` defaults unless noted.

Machine: MacBook Pro 2017, Intel ____, ____ GPU, macOS ____. Displays: ____.

| Clip | Shown | Late | Dropped | Avg ms | Worst ms | CPU % | GPU % (Activity Monitor) | Notes |
|---|---|---|---|---|---|---|---|---|
| h264-1080p30 | | | | | | | | |
| h264-1080p60 | | | | | | | | |
| h264-2160p30 | | | | | | | | |
| h264-2160p60 | | | | | | | | |
| hevc-1080p30 | | | | | | | | |
| hevc-1080p60 | | | | | | | | |
| hevc-2160p30 | | | | | | | | |
| hevc-2160p60 | | | | | | | | |
