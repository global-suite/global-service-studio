# Video benchmark

`GSSVideoBench` measures heavy video playback before the media layer relies on it. [ADR 0008](adr/0008-media-layer-key-output-and-video.md) requires 4K H.264 and HEVC at 30 and 60 frames per second on two outputs to be measured on the Intel test machine, the 2017 MacBook Pro ([ADR 0002](adr/0002-minimum-macos-13.md)). The supported limits in the documentation come from these results.

It plays video the way the app will: AVPlayer decodes each file once with the hardware decoder, `AVPlayerItemVideoOutput` hands out BGRA pixel buffers, `CVMetalTextureCache` turns them into Metal textures without a CPU copy, and every output window draws the same texture at the display refresh. Audio plays through the default output device.

It is a developer tool, separate from the app. Its console output is in English only.

## Make the test clips

```bash
swift run -c release GSSVideoBench make-clips ~/Desktop/gss-clips   # about 1.8 GB, several minutes
```

`make-clips <dir>` takes `--seconds N` for the clip length, 20 by default. It writes eight clips, all invented: a moving gradient with noise, a moving square, the frame number and a 440 Hz tone in AAC.

| Codec | Sizes | Frame rates | Bitrate |
|---|---|---|---|
| H.264 and HEVC | 1920×1080 and 3840×2160 | 30 and 60 | 20 Mbit/s (1080p30) to 80 Mbit/s (2160p60) |

If the Mac cannot encode HEVC, those clips are skipped with a message.

Playing the clips and measuring them (`play`, `run-all`) is added next.
