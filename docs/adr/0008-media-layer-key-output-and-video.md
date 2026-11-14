# 0008. Media layer, key output and video playback

- Status: Accepted
- Date: 2026-11-13

## Context

Phase 1 step 5 adds backgrounds and video. Until now the audience output has drawn the slide text directly on black, so the slide and what is behind it are one picture. Three needs make that insufficient.

**Backgrounds that live apart from slides.** Operators expect a background video to keep playing while slides change, and to clear the words while the background stays. Churches want a default background for a song, and sometimes a different one for a part, such as the chorus.

**Lyrics for a video switcher.** Many churches mix lyrics over the live camera on a hardware switcher. The Mac sends the lyrics over a solid key color to a switcher input, as if it were another display, and the switcher removes that color. The key color depends on how the switcher is set up: green, blue or an exact value. More advanced setups send fill and key as separate signals, or send frames over the network.

**Heavy video with sound.** Services include full-screen videos in 4K and Full HD at high bitrates, with audio. They must play without dropped frames on the slowest supported machine, an Intel Mac from 2017 ([ADR 0002](0002-minimum-macos-13.md)), and reach several outputs at once.

The layer stack already exists in `OutputLayer`, and [the architecture](../architecture.md) already names looks and treats chroma and alpha key as ways of sending a look. This ADR decides how they are built.

## Decision

### Outputs are composited from layers

Every output draws the `OutputLayer` stack from bottom to top. The slide layer draws only the slide's content, such as text and graphics, over transparency. Backgrounds belong to the media layer. Each layer changes and clears on its own:

- Clear Slide empties the slide layer and leaves the background.
- Clear Background empties the media layer and leaves the words.
- Clear All empties both.

### Output roles and looks

An output has a **role**, and the role sets its default **look**: which layers it shows.

| Role | Shows | Behind it |
|---|---|---|
| Audience | Every layer | Screen color |
| Key | Slide, props and messages | The output's key color |
| Stage | Its own teleprompter layout | Black |

- A key output never shows the media layer or video input. A song's background video can play in the room while the switcher still receives words over the key color.
- The key color is a setting of each output, stored as a hex color. The interface offers green, blue and a custom color.
- A display holds one output. Choosing a display already in use by another output moves that output there.
- Editing a look layer by layer is a Phase 2 feature built on this model. Phase 1 uses the role defaults.
- Alpha key output, which sends fill and key as separate signals, comes later with NDI and Syphon. Each is a way to send the same look. A closed SDK they need goes in an optional module behind an interface the project owns ([ADR 0006](0006-extensibility-and-live-performance.md)).

### Backgrounds are cues for the media layer

A background is content of the media layer, not part of how lyrics look. That is why a song may name one without breaking the rule in [ADR 0005](0005-file-format-design.md) that a song stores no styling: the look of each output still decides whether the media layer is shown at all.

The media layer shows whatever cue went live most recently:

1. **Theme background.** The theme's `background` applies while nothing else has been chosen.
2. **Song background.** When a song goes live, its default background goes live with it.
3. **Part background.** When the first slide of a part that names a background goes live, that background goes live. Leaving the part does not undo it. The next cue, or the operator, changes it.
4. **Operator.** Choosing a background from the media bin replaces the current one at once. Clear Background removes it until the next cue.

If the cue going live has the same media as the background already showing, the media keeps playing. A chorus that repeats does not restart its video.

The song format gains one optional field, `backgrounds`. Older readers keep it as an unknown field, so the format version stays 1 and no migration is needed:

```json
"backgrounds": {
  "default": { "kind": "video", "media": { "path": "Media/waves.mp4", "sha256": "…" } },
  "sections": { "c": { "kind": "image", "media": { "path": "Media/light.jpg", "sha256": "…" } } }
}
```

Each value has the same shape as a theme `background`. Media is a library-relative path plus a content hash. A plan item can override the song's backgrounds for one service when the plan format is built. A background on a single slide is left to slide actions in Phase 3.

### Video is decoded once, by hardware, and shared

- **Decoding.** AVFoundation decodes each video, which uses the hardware decoder through VideoToolbox. Frames are read with `AVPlayerItemVideoOutput` as `CVPixelBuffer`s and turned into Metal textures through `CVMetalTextureCache`, without copying them through the CPU.
- **Shared frames.** A video playing on several outputs is decoded once. Every output composites the same texture at its own size, so one 4K file feeds a 1080p screen and a 4K screen alike.
- **Prepared before going live.** A media item is opened and its first frame decoded before it goes live, so a cue starts on the next frame. Background loops repeat without a visible gap.
- **Two kinds of media.** Backgrounds loop and are muted by default. A full-screen video plays once with sound and transport controls (play, pause, seek), and replaces the background in the media layer while it plays.
- **Audio.** Video sound goes to an audio device chosen in Settings, so it can reach the mixing desk instead of the Mac's default output.
- **Formats.** H.264 and HEVC are supported on every machine, because both have hardware decoding on Apple silicon and on the 2017 Intel machines. Any other format AVFoundation plays is accepted. Formats without hardware decoding on a machine, such as ProRes on Intel, are marked as heavy for that machine instead of being refused.
- **Measured before it is relied on.** Before the media bin is built, a benchmark plays 4K H.264 and HEVC files at 30 and 60 frames per second on two outputs on the Intel test machine, and records dropped frames, CPU and GPU use. The supported limits in the documentation come from that measurement, not from this ADR.

## Alternatives considered

- **Backgrounds inside the theme only.** Simple, but one theme would be needed for every background, and a part could never have its own.
- **A background stored per slide in the song.** It is the most flexible, but songs do not store slides ([ADR 0005](0005-file-format-design.md)), so it would tie the song to one theme's line breaks. Parts give nearly the same control, and slide actions cover the rest.
- **Burning the key color into the theme.** Rejected: the same song would need a second theme for the switcher, and a background in the theme would leak into the key signal.
- **`AVPlayerLayer` in each output window.** The easiest way to show video, but each layer decodes and composites on its own path. Several outputs would multiply decoding work, and the render engine could not composite text over the frames it owns.
- **A bundled decoder, such as FFmpeg.** It plays more formats, but it adds a large dependency with licensing and signing costs, and it gives up the hardware path that makes 4K possible on the Intel machine. It can come back later as an optional importer that converts files.

## Consequences

- One song serves the room, the switcher and the stage at the same time, each through its own look.
- Clear Background, background videos that survive slide changes, and the key output all come from the same layer model.
- Repeated parts keep their video playing, which matches how operators run songs with repeated parts.
- The render engine owns video frames, which is more work up front than dropping an `AVPlayerLayer` into a window.
- Per-part backgrounds are an additive field. Files that use it still open in older versions, without the backgrounds.
- The 4K limits are unknown until the benchmark runs on the Intel machine. ProRes 4K may not be playable there.
- Chroma keying depends on the switcher. The app only guarantees an exact, solid key color with no gradients or compression in it.
