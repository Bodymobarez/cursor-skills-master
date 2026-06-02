---
name: video-social-export-specs
description: >-
  Ship-correct 2026 export specs for TikTok, Reels, Shorts, YouTube, LinkedIn, X — verified aspect ratios,
  pixel sizes, UI safe zones, length caps, bitrate/codec targets, caption rules, and a master→variants
  strategy. Use to set canvas/safe zones BEFORE generation and to export the final deliverable pack.
---

# Social & Platform Video Specs (2026)

**Mandate:** decide aspect ratio and safe zones **before** you generate a single clip — they constrain the
whole pipeline. The universal master is **1080×1920, 9:16** (covers TikTok, Reels, Shorts, Stories, LinkedIn
creator, Pinterest, Snapchat); derive 16:9 / 4:5 / 1:1 from it. Assume **muted autoplay** — captions are not optional.

## When to use / NOT use

- **Use** to lock canvas + safe zones at brief time, and to produce platform-correct exports at the end.
- **NOT** for the encode mechanics themselves — that's `video-ffmpeg-post-production`.

## Canvas decision matrix

| Platform / placement | Ratio | Pixels | Max length |
|----------------------|-------|--------|-----------|
| TikTok | 9:16 | 1080×1920 | up to 10 min (file < 500 MB) |
| Instagram Reels | 9:16 | 1080×1920 | 90 s |
| Instagram Feed (tall / square) | 4:5 / 1:1 | 1080×1350 / 1080×1080 | 60 s |
| YouTube (landscape) | 16:9 | 1920×1080 (4K better) | 12 h |
| YouTube Shorts | 9:16 | 1080×1920 | ≤ 60 s (3 min eligible) |
| LinkedIn feed | 1:1 or 9:16 | 1080×1080 / 1080×1920 | up to 10 min |
| X (Twitter) | 16:9 or 1:1 | 1920×1080 / 1080×1080 | varies |

**If you export once, export 9:16 1080×1920.** For feed posts specifically, 4:5 (1080×1350) occupies more screen and tends to outperform.

## UI safe zones (1080×1920 canvas) — keep text/logo/CTA inside

| Platform | Top blocked | Bottom blocked | Sides |
|----------|------------:|---------------:|------|
| TikTok | ~150–220 px | ~350–480 px | right ~180, left ~60 |
| Instagram Reels | ~220 px | ~450 px | right ~120 |
| YouTube Shorts | ~150 px | ~250–400 px | right ~160, left ~60 |
| LinkedIn | ~80–150 px | ~120–400 px | ~40 |

Rule of thumb: keep essential content between **Y≈220 and Y≈1440** and within the center ~80% width. Put the hook in the **upper-middle third** (first 1–2 s), CTA above the bottom UI band.

## Length / pacing

| Platform | Sweet spot |
|----------|-----------|
| TikTok | 15–34 s |
| Reels | 15–90 s (ads < 15 s) |
| Shorts | ≤ 60 s |
| LinkedIn | 30–90 s |

## Encode targets (per platform)

| Setting | 9:16 social | YouTube 16:9 |
|---------|-------------|--------------|
| Container / codec | MP4 / H.264 High | MP4 / H.264 High (H.265 for 4K HDR) |
| Pixel format | yuv420p | yuv420p |
| 1080p bitrate | 8–12 Mbps (VBR 2-pass) | 8 Mbps@30 / 12 Mbps@60 |
| 4K bitrate | — | 35–45 Mbps@30 |
| Audio | AAC, ≥128 kbps, 48 kHz | AAC-LC, 384 kbps, 48 kHz |
| Loudness | ≈ −14 LUFS / −1.5 dBTP | ≈ −14 LUFS |
| Color | Rec.709 (SDR) | Rec.709 (SDR) / Rec.2020 (HDR) |
| Flags | `+faststart` | `+faststart`, closed GOP ½ fps |

```bash
# Universal social-safe export
ffmpeg -i master.mp4 -c:v libx264 -profile:v high -pix_fmt yuv420p -crf 20 \
  -maxrate 12M -bufsize 24M -c:a aac -b:a 192k -ar 48000 -movflags +faststart final_9x16.mp4
```

## Captions (mandatory for social)

- Assume **no audio** — the message must read silently. 2 lines max, ~32–42 chars/line, high-contrast box/outline.
- Burn-in for TikTok/Reels/Shorts (survives re-upload + most viewers never tap CC); soft subs for YouTube/LinkedIn (selectable, multilingual). See ffmpeg skill.
- **Arabic / RTL:** RTL caption file, correct language tag, Arabic font; keep within safe zone (don't collide with right-side action rail).

```srt
1
00:00:00,400 --> 00:00:02,200
اكتشف الخدمة الجديدة

2
00:00:02,200 --> 00:00:05,000
ووفّر وقتك اليوم
```

## Hook rules (first frames decide the play)

- Motion on **frame 1** (no slow fade-in/black intro on TikTok/Shorts).
- Claim or pattern-interrupt in **< 2 s**; put the brand reveal after the hook, not before.
- Hook text in the upper-middle third, inside safe zone — never behind the caption/CTA band.

## Master → variants strategy

```
master_9x16_1080x1920.mp4         # generate + edit here (the safe-zone-aware master)
 ├─ final_9x16.mp4                 # TikTok / Reels / Shorts / Stories
 ├─ final_16x9.mp4                 # YouTube / X / LinkedIn webinar (pad or reframe, don't auto-letterbox)
 ├─ final_4x5.mp4                  # IG / FB feed (crop to 1080×1350)
 captions_ar.srt  captions_en.srt
 thumb_1080.jpg
```

Reframe deliberately (recompose subject) rather than letting the platform auto-letterbox a 16:9 into a Shorts slot (→ black bars, dead engagement).

## Edge cases / gotchas

- **Uploading 16:9 to Shorts/Reels** → letterboxed with huge bars. Always deliver native 1080×1920.
- **CTA/logo in the bottom 400 px** on TikTok → hidden behind caption + buttons. Move up.
- **Over-bitrate** doesn't beat platform recompression — match targets; excess just inflates file size and upload time.
- **File-size caps** (TikTok < 500 MB; iOS Reels ~287 MB) → cap bitrate/length for long edits.
- **Wrong pixel format** (yuv444/10-bit) → playback issues; force yuv420p.

## Agent checklist

```
- [ ] Aspect + safe zones locked BEFORE generation
- [ ] Master is 1080×1920 9:16 unless brief says otherwise
- [ ] Essential content within Y 220–1440 + center 80% width
- [ ] Hook + motion in first 1–2 s; CTA above bottom UI band
- [ ] Captions present (burn social / soft YouTube); Arabic RTL correct
- [ ] H.264 High, yuv420p, +faststart, ≈ −14 LUFS, AAC 48 kHz
- [ ] Variants reframed (not auto-letterboxed); deliverable pack complete
```

## Anti-patterns

- One 16:9 file dumped to every platform → bars on vertical feeds, poor reach.
- No captions ("the VO explains it") → ~85% muted plays miss the message.
- Slow branded intro before the hook → swipe-away before the value lands.
- Trusting platform auto-crop to protect your logo/CTA — it won't.

## References

- YouTube recommended specs: https://support.google.com/youtube/answer/4603579
- Meta (Reels/Feed) specs: https://www.facebook.com/business/help (Reels video specs)

## Related

`video-ffmpeg-post-production`, `remotion-programmatic-video`, `video-ai-production-workflow`, `ai-video-storyboard-multishot`
