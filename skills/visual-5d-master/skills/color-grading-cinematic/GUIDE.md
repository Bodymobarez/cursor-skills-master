---
name: color-grading-cinematic
description: >-
  Grade for a filmic look at principal depth: log/HDR footage, a color-managed pipeline (ACES 2.0 /
  DaVinci RCM), LUTs done right, scope-driven grading (waveform / parade / vectorscope), primary →
  secondary → shot-matching, and real recipes for DaVinci Resolve 20 and ffmpeg (zscale, lut3d,
  curves, HDR→SDR tonemap). The grade is where the "5D" cinematic-light axis is finished. Color-manage
  or you're guessing.
---

# Cinematic Color Grading

## Mandate

Finish the **cinematic-light axis of "5D"** — depth, mood, and a consistent filmic look across every
shot — inside a **color-managed pipeline** so creative decisions translate predictably from your
monitor to Rec.709 web, P3 cinema, and HDR. Ungraded log is not a look; un-color-managed grading is
guessing. "5D" is a quality bar, not a format; the grade is one of its four pillars.

## When to use / NOT use

- **Use** to grade footage/renders: normalize log/RAW, build a show look, match shots, do
  secondaries, and deliver SDR/HDR. Pairs with `cinematic-5d-video-production` (finishing stage) and
  `3d-render-motion-graphics` (grading EXR renders).
- **NOT** for: palette/contrast *design systems* for UI/brand (→ `color-design-master`), still-image
  retouch (→ `image-5d-pro`), or editorial/conform (that precedes the grade). Grade only after
  **picture lock**.

## Mental model — the color-managed pipeline

```
INPUT TRANSFORM        interpret each source (Log-C/S-Log3/V-Log/RAW/sRGB) → scene-linear working space
  ↓
WORKING SPACE          grade in a wide-gamut scene-referred space (ACEScct or DaVinci WG/Intermediate)
  ↓  NORMALIZE          undo log → neutral, balanced starting point (NOT a look yet)
  ↓  PRIMARY            exposure · white balance · contrast · saturation — whole frame, scopes-driven
  ↓  SHOT MATCH         every shot in a scene matches the hero shot
  ↓  LOOK / SECONDARY   show LUT / creative look · qualifiers · power windows · curves
  ↓
OUTPUT TRANSFORM       map working space → delivery (Rec.709 g2.4 / P3 / Rec.2020 PQ) per target
```

Two professional ways to manage it (don't freestyle gamma):

- **ACES 2.0** — cross-facility/VFX standard. 2026 brings a new **JMH** appearance model (Hellwig
  2022 / CIECAM-style), **AP1** working primaries, a single combined **Output Transform** (replaces
  RRT+ODT), and volumetric gamut mapping (kills the old ACES 1.x red-channel inversion on neon/LED).
  With ACES 2.0, **disable** the separate Reference Gamut Compression (its mapper is built in).
- **DaVinci RCM** (DaVinci Wide Gamut + Intermediate) — Resolve-centric, fast to set up, excellent for
  single-facility work. Pick ACES when VFX/multi-vendor/archival interop matters; RCM otherwise. Both
  are valid; **choose one and stay in it.**

## Log / RAW / HDR — what you're starting from

- **Log** (Arri **Log-C**, Sony **S-Log3**, Panasonic **V-Log**, etc.) = flat, low-contrast, preserves
  dynamic range. **Don't grade log raw** — apply the correct **input transform / CST** to normalize
  first, or every wheel behaves wrong.
- **RAW** (BRAW, R3D, ProRes RAW) = debayer + pick input color space/ISO in the project.
- **HDR**: grade in HDR (Rec.2020 **ST.2084/PQ**, e.g. 1000-nit) on a real HDR reference monitor, then
  derive SDR via a **trim pass** — don't auto-downconvert and hope.
- **Identify the source first** (MediaInfo / clip attributes) and set its input space explicitly; a
  mislabeled input is the #1 cause of "the grade looks broken on export".

## Scopes — grade by the scopes, confirm with the eyes

Your monitor lies (uncalibrated, ambient light, fatigue). Scopes don't.

| Scope | Reads | Use for |
|-------|-------|---------|
| **Waveform (luma)** | brightness 0–100 IRE/1023 | expose: blacks ~0, whites ≤ ~100 (no illegal clipping) |
| **RGB Parade** | R/G/B levels separately | **white balance** — align neutrals; spot color casts |
| **Vectorscope** | hue + saturation (skin line!) | saturation sanity; push skin toward the skin-tone line |
| **Histogram** | tonal distribution | overall exposure spread, clipping at either end |

Calibrate your display (or use a reference monitor); set legal range for the target (broadcast
16–235 / full for web). If it looks great but the waveform clips at 1023, **fix the waveform**.

## Primary → secondary → shot match

1. **Primary (whole frame)**: set black point + white point on the waveform, neutralize with the
   parade (lift/gamma/gain or offset), set contrast and overall saturation. Goal = a *neutral,
   correct* image — not yet a look.
2. **Shot match**: grade the **hero shot** of a scene, then match every other shot's exposure, white
   balance, and contrast to it (use stills/split-screen + scopes). Continuity beats individually-pretty
   shots.
3. **Look / secondary**: apply the **show LUT** or build the creative look (curves, color warping,
   split-tone). **Secondaries**: HSL **qualifiers** (e.g. isolate skin, sky), **power windows** (vignette,
   relight a face), tracked. Keep it motivated.

## DaVinci Resolve 20 — workflow + node recipe

Set **Project Settings → Color Management** once: *DaVinci YRGB Color Managed* (RCM) **or** *ACEScct*;
set Output Color Space to your delivery (**Rec.709 Gamma 2.4** for web/broadcast, **P3-D65** cinema,
**Rec.2020 ST2084** HDR). Then a clean node tree per clip:

```
Node 1  CST / input transform   (Source log/gamut → working)  — or rely on RCM/ACES auto input
Node 2  Primary balance         (offset to neutral via Parade; set black/white on Waveform)
Node 3  Contrast / pivot        (filmic contrast; protect skin)
Node 4  Secondary — skin        (HSL qualifier → soften/warm; track)
Node 5  Look / show LUT         (creative LUT here, NOT on the camera-original)
Node 6  Power window vignette   (subtle, draw the eye)
Node 7  CST out / trim          (working → delivery; HDR→SDR trim if needed)
```

Order matters: **normalize before you stylize**, put the creative LUT late (Node 5), never bake it onto
the raw log. Use **Compare/stills** for shot match; **versions** for client options; **groups** for
scene-wide pre/post-clip grades.

> 2026 gotcha (verified): a system-vs-OFX color-management mismatch bit some ACES setups in **Resolve
> 20** and was fixed in **Resolve 21** — keep working spaces consistent if you flip between system
> management and OFX plugins.

## LUTs — done right (and their limits)

- **A LUT is a fixed transform, not a colorist.** Three kinds: **technical/conversion** (e.g. Log-C→
  Rec.709 — a *transform*), **creative/look** (a stylized grade), and **calibration** (display).
- **Apply on a normalized image** at the right point — a look LUT dumped on raw log clips and crushes.
- **Balance first, LUT second, trim after.** Don't "fix" exposure by stacking LUTs.
- Build/export `.cube` LUTs from a hero grade to apply elsewhere (Resolve, ffmpeg, OBS, engines).
- 3D LUTs (e.g. 33³) interpolate — they can band on extreme grades; grade natively for hero work,
  LUT for consistency/scale.

## ffmpeg recipes (automation, dailies, scale — copy/paste)

ffmpeg won't replace a colorist, but it's the right tool for batch transforms, applying a `.cube`,
proxies, and HDR→SDR at scale. **Color management here is manual** — tag your outputs.

Apply a creative/technical 3D LUT (`.cube`), high quality:

```bash
ffmpeg -i input.mov -vf "lut3d=look.cube" \
  -c:v prores_ks -profile:v 3 -pix_fmt yuv422p10le output_prores.mov
# delivery H.265 instead: -c:v libx265 -crf 18 -preset slow -pix_fmt yuv420p10le
```

HDR (Rec.2020/PQ) → SDR (Rec.709) tonemap — the floating-point pipeline that *actually* works
(verified pattern; `desat=0` keeps highlight color; `gbrpf32le` prevents banding):

```bash
ffmpeg -i input_hdr.mp4 -vf "\
zscale=t=linear:npl=100,format=gbrpf32le,\
zscale=p=bt709,tonemap=hable:desat=0,\
zscale=t=bt709:m=bt709:r=tv,format=yuv420p" \
  -c:v libx264 -crf 18 -preset slow \
  -colorspace bt709 -color_primaries bt709 -color_trc bt709 \
  -c:a copy output_sdr.mp4
# too dark? swap tonemap=hable → tonemap=reinhard. GPU path: libplacebo (Vulkan) does gamut+metadata.
```

GPU tonemap with `libplacebo` (faster, broadcast-grade), downscale to 1080p in one filter:

```bash
ffmpeg -init_hw_device vulkan -i input_hdr.mkv -vf "\
libplacebo=w=-1:h=1080:tonemapping=hable:peak_detect=true:gamut_mode=perceptual:\
colorspace=bt709:color_trc=bt709:color_primaries=bt709:range=limited:dithering=blue:format=yuv420p" \
  -c:v libx264 -crf 18 -preset slow -c:a copy output_sdr_1080.mp4
```

Quick non-managed tweak (use sparingly — DaVinci is the real grade): lift/gamma/gain via `curves` /
contrast+saturation via `eq`:

```bash
ffmpeg -i in.mp4 -vf "curves=r='0/0.02 0.5/0.5 1/0.96':b='0/0.05 1/0.92',eq=contrast=1.08:saturation=1.06" out.mp4
```

> Reality check: prefer the **`tonemap`/`libplacebo`** pipeline over baking HDR→SDR into a single
> `lut3d` — a static LUT can't do proper peak detection/transfer handling and needs heavy tweaking.

## Edge cases / gotchas

- **Mislabeled input** (treating Rec.709 as log, or wrong log curve) → everything downstream is wrong.
- **Grading on un-calibrated / SDR monitor for HDR** → invalid; use a reference display.
- **Skin tone drift** after a heavy look → re-check the vectorscope skin line; protect skin with a
  qualifier.
- **Illegal levels** on broadcast (clipping > 100 IRE / crushed blacks) → fix on the waveform.
- **Banding** from 8-bit pipelines or aggressive grades → work in 10/12-bit, add dither (Resolve dither
  / ffmpeg `dithering=blue`).
- **Baking a look LUT onto camera-original** → unrecoverable; keep it a late, removable node.
- **AI-generated footage** often arrives already contrasty/saturated — normalize before adding a look,
  or you double up.

## Performance / render-cost

- **Optimized media / proxies** for the offline; render cache (Resolve) for heavy node trees / noise
  reduction / OFX so playback stays real-time.
- GPU drives grading + ffmpeg `libplacebo`/NVENC; batch dailies/LUT applies with ffmpeg overnight.
- Final render from the **mezzanine** (ProRes/EXR), not a re-compressed file; export once per delivery
  spec. Track render-hours for farm/cloud finishing.

## Rights / licensing & brand safety

- **LUTs/looks**: many "film emulation" LUT packs are licensed per-seat/project — confirm commercial
  use; don't redistribute purchased `.cube` files in deliverables.
- **Show look as IP**: deliver the project/LUT only per contract; a signature grade can be a brand asset.
- **Film-stock emulation names** (e.g. specific stock/brand trademarks) — market your look generically
  unless licensed.
- **Footage rights** are upstream (talent/location/stock) — verify before finishing (see
  `cinematic-5d-video-production`).

## Consistency / scale

- **Show LUT + node-tree template** as the single source of look; apply across all shots/episodes via
  groups/stills/`.cube`. Re-grade by editing the template, not 200 clips.
- **Reference stills** library for shot match; lock the hero grade per scene first.
- **Pull brand accent colors** from `color-design-master` tokens if the grade must echo a brand
  palette (e.g. a brand teal in the shadows).

## QA / review

```
- [ ] Picture LOCKED before grading; sources' input transforms set correctly
- [ ] Color management chosen (ACES 2.0 or RCM) and consistent end-to-end
- [ ] Primary neutral via Parade/Waveform; legal levels for target
- [ ] Every shot matches the scene hero (continuity), checked on scopes + split
- [ ] Skin on the vectorscope skin line after the look
- [ ] Look LUT is a late, removable node — never baked on camera-original
- [ ] HDR graded on reference display; SDR via trim, not blind downconvert
- [ ] 10/12-bit pipeline; no banding/illegal clipping; QC on the delivery file
```

## Delivery specs (color space / transfer / codec)

| Target | Output transform / color | Codec | Levels / notes |
|--------|--------------------------|-------|----------------|
| **Web / streaming SDR** | **Rec.709, Gamma 2.4 (BT.1886)** | H.264/H.265/AV1, 10-bit pref. | tag `bt709` primaries/trc/matrix; ~ -14 LUFS |
| **Broadcast** | Rec.709 g2.4 | per spec (ProRes/XDCAM) | legal 16–235; **-23 LUFS (EBU R128)** / -24 LKFS |
| **HDR streaming** | **Rec.2020 ST.2084 (PQ)** (or HLG) | H.265/AV1 10-bit | HDR10 metadata / Dolby Vision per platform |
| **Cinema** | **DCI-P3** | DCP (JPEG2000) | separate theatrical pass |
| **Mezzanine/archive** | scene or Rec.709/P3 | **ProRes 422 HQ / 4444** | the master you re-encode from |

Always **trim HDR→SDR** as its own pass; export each delivery from the mezzanine; verify with scopes
on the *exported* file. Loudness/true-peak per platform (true-peak ≤ -1 dBTP).

## Accessibility & i18n / RTL

- **Don't carry meaning in color alone** — if the grade must signal something (a UI/brand cue baked
  in), pair with luma/shape so CVD (color-blind) viewers aren't excluded (see `cvd-colorblind-safe`).
- **Contrast for burned-in text/captions**: ensure subtitles/lower-thirds clear ~4.5:1 against the
  *graded* (often darkened) image — re-check after the look, not before.
- **Photosensitivity**: avoid grades that amplify strobing/flashing; cap rapid luma swings.
- **i18n/RTL**: caption rendering and any localized burn-ins must support the target script/RTL;
  verify the grade's contrast holds for each localized text version.

## Anti-patterns

- Grading log/RAW without an input transform; freestyling gamma instead of managed color.
- Dumping a creative LUT on the camera-original and "fixing" exposure with more LUTs.
- Trusting an uncalibrated monitor over the scopes; grading HDR on an SDR display.
- Per-shot "pretty" grades that don't match within a scene (continuity breaks).
- 8-bit pipeline / aggressive grade → banding; ignoring legal levels for broadcast.
- Baking HDR→SDR with a single static lut3d instead of a proper tonemap/peak-detect pipeline.
- Re-encoding a delivery from an already-compressed file instead of the mezzanine.

## Agent checklist

```
- [ ] Source input spaces identified + transformed; one color-management mode (ACES/RCM)
- [ ] Scope-driven primary (neutral) → shot match → look (late LUT) → secondaries
- [ ] HDR on reference display; SDR trim pass; 10/12-bit; legal levels
- [ ] DaVinci node order: normalize → balance → contrast → secondary → look → window → out
- [ ] ffmpeg only for batch/transform/tonemap; outputs tagged (bt709 etc.)
- [ ] Loudness + captions contrast to spec; QC on the exported delivery file
- [ ] LUT/look licensing cleared; mezzanine kept; per-target exports verified
```

## References (2026-current)

- DaVinci Resolve color management / ACES: https://www.blackmagicdesign.com/products/davinciresolve
- ACES (Academy): https://acescentral.com/ · ACES 2.0 docs: https://docs.acescentral.com/
- ffmpeg filters (zscale, lut3d, tonemap, libplacebo): https://ffmpeg.org/ffmpeg-filters.html
- EBU R128 loudness: https://tech.ebu.ch/publications/r128 · ITU BT.2100 (HDR): https://www.itu.int/rec/R-REC-BT.2100

## Related

`cinematic-5d-video-production` (finishing stage), `3d-render-motion-graphics` (grade EXR renders),
`image-5d-pro` (this master); `color-design-master`, `cvd-colorblind-safe`,
`wcag-contrast-color-pairs` (color-design-master); `video-ffmpeg-post-production` (video-ai-master).
