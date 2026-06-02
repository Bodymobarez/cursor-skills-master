---
name: video-ffmpeg-post-production
description: >-
  Production ffmpeg for AI video: normalize-then-concat, two-pass EBU R128 loudnorm, music sidechain
  ducking, scale/crop/pad per aspect, burn or soft subtitles (incl. RTL Arabic), green-screen chromakey
  for avatars, color/faststart, thumbnails, QA probes. Use to assemble + master generated clips.
---

# Video Post-Production (ffmpeg)

**Mandate:** AI clips arrive with **mismatched fps, codecs, color, and loudness**. Normalize first, then
assemble — or concat stutters and audio jumps shot to shot. Loudness is **two-pass measured**, captions are
real (muted autoplay), and every master ends `+faststart`. Use bundled ffmpeg (`npx remotion ffmpeg`) if no system install.

## When to use / NOT use

- **Use** to concat, mix, normalize loudness, burn captions, key avatars, and produce platform masters.
- **NOT** for animated/branded overlays or data-driven layout — that's `remotion-programmatic-video`.

## Step 0 — normalize before concat (the step everyone skips)

```bash
# Force identical fps/timebase/codec/SAR so the concat demuxer doesn't stutter or fail.
for f in shots/raw/*.mp4; do
  ffmpeg -i "$f" -vf "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,fps=30,setsar=1" \
    -c:v libx264 -crf 18 -preset medium -pix_fmt yuv420p -c:a aac -ar 48000 "shots/norm/$(basename "$f")"
done
```

## Concat

```
# shots.txt
file 'shots/norm/01.mp4'
file 'shots/norm/02.mp4'
```

```bash
ffmpeg -f concat -safe 0 -i shots.txt -c copy assembled.mp4              # fast path: identical encodes
ffmpeg -f concat -safe 0 -i shots.txt -c:v libx264 -crf 18 -preset medium -c:a aac assembled.mp4  # if any differ
```

For cross-dissolves/wipes between clips use the `xfade`/`acrossfade` filters (or do transitions in Remotion `TransitionSeries`).

## Aspect conversion

| Goal | Filter |
|------|--------|
| Fill 9:16 (center **crop**, lossy edges) | `scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920` |
| Fit 9:16 (**pad**, keep all pixels, bars) | `scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2` |
| Blurred-bar fill (no hard letterbox) | split → blurred `boxblur` background + scaled foreground overlay |

```bash
ffmpeg -i 16x9.mp4 -vf "scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920" out_9x16.mp4
```

## Music + sidechain ducking (music dips under VO automatically)

```bash
ffmpeg -i voice.mp4 -i music.mp3 -filter_complex \
 "[1:a]volume=0.6[m];[m][0:a]sidechaincompress=threshold=0.03:ratio=8:attack=20:release=300[duck];\
  [0:a][duck]amix=inputs=2:duration=first:dropout_transition=2[a]" \
 -map 0:v -map "[a]" -c:v copy -c:a aac with_music.mp4
```

Sidechain (VO triggers the duck) beats a static `volume=0.25` — speech stays intelligible without burying the bed during pauses.

## Loudness — two-pass EBU R128 (do NOT eyeball)

Social target ≈ **-14 LUFS**, TP **-1.5 dBTP** (use -16 for broadcast-ish).

```bash
# Pass 1 — measure
ffmpeg -i with_music.mp4 -af loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json -f null - 2>&1 | tail -20
# Pass 2 — apply measured values (linear, accurate)
ffmpeg -i with_music.mp4 -af \
 "loudnorm=I=-14:TP=-1.5:LRA=11:measured_I=-22.3:measured_TP=-6.1:measured_LRA=9.4:measured_thresh=-33.1:offset=0.2:linear=true:print_format=summary" \
 -c:v copy -c:a aac -ar 48000 final_norm.mp4
```

One-pass `loudnorm` is dynamic/approximate; two-pass `linear=true` hits the target precisely and avoids pumping.

## Captions

**Burn-in (social, survives re-upload):**

```bash
ffmpeg -i final.mp4 -vf "subtitles=captions.srt:force_style='FontName=Inter,FontSize=22,PrimaryColour=&H00FFFFFF&,OutlineColour=&H99000000&,BorderStyle=3,Outline=2,Shadow=0,Alignment=2,MarginV=120'" -c:a copy final_subbed.mp4
```

**Arabic / RTL:** shape the text first or use `libass` with an Arabic font (e.g. `FontName=Cairo`). Use ASS (not SRT) for reliable RTL/positioning; ensure the font is installed/embedded or glyphs render as boxes.

**Soft subs (YouTube/LinkedIn — selectable, multilingual):**

```bash
ffmpeg -i final.mp4 -i en.srt -i ar.srt -map 0 -map 1 -map 2 -c copy -c:s mov_text \
  -metadata:s:s:0 language=eng -metadata:s:s:1 language=ara final_soft.mp4
```

## Green-screen avatar → composite (chromakey)

```bash
ffmpeg -i bg_scene.mp4 -i avatar_green.mp4 -filter_complex \
 "[1:v]chromakey=0x00FF00:0.10:0.08[ck];[0:v][ck]overlay=(W-w)/2:H-h[out]" \
 -map "[out]" -map 1:a -c:a aac composited.mp4
```

Pull the avatar with Synthesia `green_screen` / HeyGen `webm` alpha. Tune `similarity:blend` to kill green spill without eating hair edges. (Prefer the alpha `webm` path — no keying artifacts.)

## Color / delivery hygiene

```bash
# gentle grade + Rec.709 tag + web-fast start
ffmpeg -i in.mp4 -vf "eq=contrast=1.05:saturation=1.08,format=yuv420p" \
  -colorspace bt709 -color_primaries bt709 -color_trc bt709 \
  -c:v libx264 -profile:v high -crf 20 -c:a aac -b:a 192k -movflags +faststart out.mp4
```

## Thumbnail / QA probes

```bash
ffmpeg -ss 00:00:01 -i final.mp4 -frames:v 1 -q:v 2 thumb.jpg
ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate,pix_fmt -of default=nw=1 final.mp4
ffprobe -v error -select_streams a:0 -show_entries stream=channels,sample_rate -of default=nw=1 final.mp4
```

## Reliability / scale

- Wrap recipes in a script driven by `STORYBOARD.json` (fps/aspect/resolution) so masters are reproducible.
- Use `-hwaccel`/NVENC (`h264_nvenc`) for large batches; keep CRF/libx264 for final-quality masters.
- Pin the ffmpeg version in CI (`npx remotion ffmpeg` is bundled + stable across machines).

## Edge cases / gotchas

- **VFR from AI clips** → audio desync after concat. Force CFR (`fps=30`, `-vsync cfr`) in normalize.
- **yuv444 / 10-bit** AI output → won't play on some socials. Force `-pix_fmt yuv420p`.
- **`-c copy` after a filter** silently ignores the filter — only stream-copy when not filtering that stream.
- **SRT for Arabic** mis-renders RTL → use ASS/libass + Arabic font.
- **Missing `+faststart`** → web players buffer before playback (moov atom at end).

## Agent checklist

```
- [ ] All shots normalized to one fps/codec/resolution/SAR before concat
- [ ] CFR enforced (no VFR desync)
- [ ] Loudness two-pass to -14 LUFS / -1.5 dBTP
- [ ] Captions burned for social; soft+multilang for YouTube/LinkedIn
- [ ] pix_fmt yuv420p, +faststart, Rec.709 on every master
- [ ] ffprobe verified codec/res/fps/audio before delivery
```

## Anti-patterns

- Concatenating mixed-fps/codec clips with `-c copy` → stutter, broken audio.
- One-pass loudnorm "good enough" → pumping, off-target levels across platforms.
- Static music volume instead of sidechain ducking → buried or competing VO.
- Eyeballing aspect crop without checking the platform safe zone (`video-social-export-specs`).

## References

- loudnorm (EBU R128): https://ffmpeg.org/ffmpeg-filters.html#loudnorm · concat: https://trac.ffmpeg.org/wiki/Concatenate
- subtitles/ass: https://trac.ffmpeg.org/wiki/HowToBurnSubtitlesIntoVideo

## Related

`video-social-export-specs`, `remotion-programmatic-video`, `ai-video-audio-voiceover`, `video-ai-production-workflow`
