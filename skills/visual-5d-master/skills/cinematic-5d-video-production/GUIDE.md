---
name: cinematic-5d-video-production
description: >-
  Produce ultra-premium cinematic video at principal depth: pre-pro & shot/lens language (focal
  length, DOF, movement), 3D camera moves & depth/parallax, virtual production (UE5.6 / LED volume /
  ICVFX), hybrid AI generation (Veo/Kling/Runway via fal — see video-ai-master), VFX/compositing,
  cinematic grade, and HDR/codec mastering. "5D" = a quality bar (photoreal depth + 3D form +
  cinematic light + motion), NOT a codec. Use for cinematic ads, hero films, and title sequences.
---

# Cinematic 5D Video Production

## Mandate

Ship video that reads as **shot on a cine camera by a crew that knows light** — whether the pixels
came from a sensor, Unreal Engine, or a diffusion model. The job is *coherence*: one focal-length
logic, one lighting grammar, one color pipeline, one delivery spec across every shot.

**"5D" is a quality bar, not a format.** There is no "5D codec" and no "5D camera". 5D = four real,
measurable craft axes stacked on one shot:

1. **Photoreal depth** — atmospheric perspective, haze, occlusion, correct exposure falloff.
2. **3D form** — volume read through lighting and lens, not flat "sticker" subjects.
3. **Cinematic lighting** — motivated, directional, with ratio and color temperature intent.
4. **Motion / parallax** — a camera that moves through space with real depth cues.

If a shot is missing one of those four, it isn't "5D" — it's a flat clip. Everything below is in
service of hitting all four, repeatably, on budget.

## When to use / NOT use

- **Use** for cinematic ads, brand films, music videos, hero/title sequences, product reveals — any
  piece where the *look* is the deliverable and you control the full pre-pro → master pipeline.
- **NOT** for: pure talking-head/explainer (→ `ai-avatar-presenter-video` in `video-ai-master`),
  exact branded text/charts/data overlays (→ `remotion-programmatic-video`), choosing *which* AI
  model (→ `ai-video-models-selection`), or wiring the generation API (→ `ai-video-api-fal-runway`).
  This skill is the **creative-direction + integration spine**; it routes to those for execution.

## Mental model — the pipeline (each stage gates the next)

```
PRE-PRO          treatment · references/mood · shot list · lens plan · color script · budget
  ↓
ACQUISITION      live cine  |  virtual production (UE5/LED)  |  AI generation  |  3D render
  ↓              (usually a HYBRID — route per shot, see matrix below)
ASSEMBLY         editorial cut · timing · selects locked BEFORE finishing
  ↓
VFX / COMP       cleanup · roto · matte · CG integration · 2.5D parallax · screen inserts
  ↓
GRADE            color-managed (ACES/RCM) · primary/secondary · shot match (→ color-grading-cinematic)
  ↓
MASTER/DELIVER   conform · codec/color-space encode · QC · captions · platform variants
```

Lock each stage before the next. Grading a cut that isn't picture-locked, or compositing on
un-graded plates, is how budgets detonate.

## Shot & lens language (the part most "AI video" people skip)

Focal length is a *storytelling* decision before it is a technical one. Pick it for the relationship
between subject, background, and viewer — not for "zoom".

| Focal (FF/35mm) | Reads as | Use for | Watch out |
|-----------------|----------|---------|-----------|
| 14–24mm | epic, distorted, immersive | establishing, architecture, dramatic POV | edge stretch on faces |
| 28–35mm | natural-wide, environmental | walk-and-talk, context + subject | still distorts close faces |
| **40–50mm** | "normal", human-eye | grounded narrative, the safe hero | can feel flat if static |
| 75–85mm | flattering portrait, isolation | beauty, interview, product hero | needs distance/space |
| 100–135mm+ | compressed, voyeuristic | tension, telephoto isolation | hard to light/track |

Three knobs that create the "cine" depth read:

- **Depth of field**: shallow (T1.4–T2.8 on a fast prime, or large sensor) separates subject from
  background → the single biggest "expensive" tell. Deep focus (T8+) = scale/realism. DOF is a
  function of aperture, focal length, and **subject-to-background distance** — move the subject off
  the wall before you open the iris.
- **Movement** (intent, not random): **dolly** (push/pull = emotional change), **truck** (lateral,
  reveals parallax), **crane/jib** (scope), **handheld** (energy/realism), **Steadicam/gimbal**
  (floating follow), **locked-off** (formal stillness), **whip pan / snap zoom** (energy beat). Each
  has a meaning; pick one per shot and commit.
- **Shutter & frame rate**: 180° shutter (1/48 at 24p) is the default cinematic motion-blur. Shoot
  48–120fps to *retime* to slow motion. Don't ship 24p with a 1/4000 shutter unless you want the
  "Saving Private Ryan" staccato look on purpose.

> **Anamorphic vs spherical**: anamorphic (2x/1.8x squeeze → 2.39:1, oval bokeh, horizontal flares)
> is the premium "cinema" tell but eats light and resolution. Spherical is cleaner/sharper/cheaper.
> Choose deliberately; don't fake anamorphic flares on a spherical-looking plate.

## 3D camera & parallax (where "5D" depth is won or lost)

Flatness is the #1 failure of AI/stock video. Build depth explicitly:

- **2.5D parallax**: separate a still or plate into depth planes (fg/mid/bg), offset their motion to
  the camera. A 35mm-equivalent push with 3 planes at different speeds reads as real space.
- **Generate depth** with **Depth Anything V2** or **MiDaS** → displacement/parallax in comp (Nuke,
  AE) or in 3D (R3F/Three.js plane displacement — see `3d-render-motion-graphics`).
- **Match the virtual camera**: when mixing CG/AI with live action, match focal length, sensor size,
  film-back, and the **same** DOF/defocus. A 24mm plate with an 85mm CG insert never composites.
- **Atmosphere = free depth**: volumetric haze/fog graded darker-to-lighter with distance is the
  cheapest, most reliable depth cue. Add it; don't fight it.

## Acquisition decision matrix — route PER SHOT

| Method | Best for | Cost/Control | Reality check |
|--------|----------|--------------|---------------|
| **Live cine** (camera crew) | faces, hero product, anything with talent | $$$$ / total | most credible, least flexible after wrap |
| **Virtual production** (UE5.6 + LED volume / ICVFX) | actor-in-environment, reflective sets, sky/landscape | $$$$ / high | final-pixel BG + in-camera light; needs a stage |
| **AI generation** (Veo / Kling / Runway via fal) | b-roll, impossible shots, fast concepting, environments | $ / medium | per-shot, ≤8–15s, drift on faces/text/hands |
| **3D render** (Blender/UE offline) | exact product, branded objects, controllable abstractions | $$ / total | slow render, but pixel-exact and re-renderable |
| **Stock/library** | filler, textures, atmosphere plates | $ / low | licensing + "I've seen this clip" risk |

Real ads are **hybrids**: live hero shots, AI/3D environments and b-roll, Remotion end-cards. The
director's job is routing each storyboard row to the right method, then unifying them in the grade.

## Virtual production (UE5 / LED volume) — the 2026 reality

In-camera VFX (ICVFX) on an LED volume is now mainstream (Epic reported ~100+ stages and 65% of
entertainment devs on Unreal at GDC 2026). The stack:

- **Unreal Engine 5.6** rendering **Nanite** geometry + **Lumen** GI, environments from **Megascans**
  + custom geo, distributed over **nDisplay** (5.7, Dec 2025, sub-ms tracking latency) to the wall.
- **Camera tracking**: Mo-Sys StarTracker / Vicon / Stype RedSpy / OptiTrack feed position + lens
  encoder data → UE updates the **inner frustum** (high-fidelity, camera-visible) vs outer frustum
  (interactive lighting only).
- **Genlock everything**; **LED processor** = Brompton; control via **Switchboard** + Remote Control
  Presets on a tablet.
- **Set exposure to Manual** in UE (auto-exposure per-viewport causes flicker — verified gotcha).

**Top gotchas:** **moiré** (camera sensor vs LED pixel grid → stop down / move back / defocus wall /
adjust pixel pitch), **tracking latency** (BG lags the move), color calibration between wall and
foreground, and parallax breaking if talent gets too close to the wall. VP shifts cost from post to
**pre-pro**: every environment must be built before the camera rolls.

## AI generation — bridge to `video-ai-master` (don't reinvent it)

This skill **does not** restate model endpoints — that's `ai-video-models-selection` and
`ai-video-api-fal-runway`. What the director must know, current to 2026:

- The landscape moved: **Kling 3.0** (native 4K/60fps, up to ~15s, multi-shot storyboard up to 6
  shots, multilingual audio) and **Veo 3.1** (native synced dialogue + SFX, 4K, fast) lead practical
  production; **Runway Gen-4.5** (GWM-1 world model, motion brushes, scene consistency) owns the
  *control surface* for film work. **Sora 2 is deprecated** (OpenAI announced wind-down; Videos API
  shutdown ~Sept 24, 2026) — **do not start a new pipeline on Sora 2**. Open-weights: **Wan 2.2 /
  LTX** for cheap iteration. **Always copy the exact model ID from the live fal card — versions drift
  and invented strings 404.**
- **Route through fal.ai** for one integration across models; use the **queue + verified webhooks**
  for batch (full pattern in `ai-video-api-fal-runway`).
- **Cinematic prompt craft** (subject · lighting · lens · movement · film stock · mood) lives in
  `ai-video-cinematic-prompts`. **Per-shot model choice** in `ai-video-models-selection`.
- **Consistency** across shots (characters, products, location) → `ai-image-to-video-consistency`
  (reference images, first-last-frame, seeds).

Per-shot prompt skeleton (hand to the cinematic-prompts skill to finish):

```text
[SHOT] Slow 35mm dolly-in, eye-level, shallow DOF (T1.8), 24fps/180° shutter.
[SUBJECT] A weathered analog watch on wet black slate, second hand sweeping.
[LIGHT] Single hard key from camera-left 45°, cool practical rim, deep falloff to black.
[ATMOS] Faint volumetric haze, water micro-droplets catching the rim light.
[GRADE] Teal-shadow / amber-highlight, low-key, filmic toe. Negative: text, logos, hands.
```

## Hybrid AI + Remotion 3D overlays (titles, UI, branded motion graphics)

Generative models are bad at exact text, brand color, and data. Composite **Remotion** (React)
overlays on top of AI/live plates — crisp typography + real 3D via `@remotion/three`.

**The four rules that make `@remotion/three` deterministic** (verified): drive *everything* with
`useCurrentFrame()` — **never** R3F's `useFrame()` (real-clock → flicker on render); pass `width`/
`height` from `useVideoConfig()`; set `layout="none"` on any `<Sequence>` inside the canvas; and for
server/Lambda render set `chromiumOptions: { gl: "angle" }`.

```tsx
// 3D logo lower-third composited over a generated/live plate (frame-driven, render-safe)
import { ThreeCanvas, useOffthreadVideoTexture } from "@remotion/three";
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig, staticFile } from "remotion";

export const HeroOverlay: React.FC<{ plate: string }> = ({ plate }) => {
  const frame = useCurrentFrame();
  const { width, height, fps } = useVideoConfig();
  const intro = spring({ frame, fps, config: { damping: 200 } });          // entrance, frame-accurate

  return (
    <AbsoluteFill>
      <ThreeCanvas width={width} height={height} camera={{ fov: 40, position: [0, 0, 6] }}>
        <ambientLight intensity={0.4} />
        <directionalLight position={[3, 4, 5]} intensity={2.2} />
        <mesh rotation={[0, interpolate(frame, [0, 90], [-0.6, 0]), 0]} scale={intro}>
          <torusKnotGeometry args={[1, 0.32, 180, 32]} />
          {/* metallic brand mark — PBR; see 3d-render-motion-graphics */}
          <meshStandardMaterial metalness={0.95} roughness={0.18} color="#d4af37" />
        </mesh>
      </ThreeCanvas>
      {/* exact brand text sits in DOM on top — perfectly crisp, themable, i18n-ready */}
    </AbsoluteFill>
  );
};
```

Use `useOffthreadVideoTexture()` to map a video as a texture **during render** (and
`useVideoTexture()` in Studio/Player). Full render/Lambda pipeline → `remotion-programmatic-video`.

## VFX / compositing essentials

- **Tools**: Nuke (node-based, film standard), After Effects (motion graphics + light comp),
  DaVinci Fusion (bundled, capable), Blender comp for 3D-native passes.
- **Always render/keep passes** for CG: beauty, depth (Z), normals, cryptomatte, motion vectors —
  so the comp can relight/defocus/grade without re-rendering.
- **Integration craft**: match grain, match black levels, add the same lens defocus/CA/halation to
  CG as the plate, contact shadows, and *edge treatment* (the giveaway on bad comps).
- **Linear, please**: composite in linear light (scene-referred), not in display-gamma sRGB, or your
  blends/glows are physically wrong. (Same principle as the grade — see color skill.)

## Edge cases / gotchas

- **AI face/hand/text drift** across shots → lock seeds + reference images; keep text out of
  generation and add it in Remotion.
- **Frame-rate soup**: AI clips at 24/25/30, live at 23.976, social at 30/60. Decide the **timeline
  fps once**; conform everything (retime, don't just "drop frames").
- **Aspect/crop**: shoot/generate with safe areas for 16:9 *and* 9:16 if you need both; don't
  center-crop a composed 16:9 to vertical and call it done.
- **Audio on silent models**: Kling/Luma/Wan are silent — plan VO/SFX/music (`ai-video-audio-voiceover`).
- **Banding** in skies/gradients → work and deliver in ≥10-bit; add subtle dither in the grade.
- **Provider URLs expire** — download AI outputs to your own storage immediately.

## Performance / render-cost

- Budget at the **shot** level: a 30s ad = ~6 shots × 5s. **Draft on cheap tiers** (Wan/fast/lite),
  promote only *approved* shots to hero tiers (Veo 4k+audio, Kling 3.0 Pro). Log `model, duration_s,
  resolution, audio, est_usd` per job; track **$ per *delivered* asset** (include retries/rejects).
- Offline 3D/comp: render **proxies** for editorial, full-res only after picture lock. Use a render
  farm / Lambda for parallelism. EXR multi-pass is big — manage storage.
- Remotion: render on Lambda for concurrency; cache assets; `gl: "angle"`.
- VP: the cost is the stage day + pre-built environments; over-runs come from un-finished UE scenes,
  not render time.

## Rights / licensing / likeness & brand safety

- **Talent/likeness**: get releases. For AI likeness/cameo, you need explicit rights; respect model
  IP-blocking flags (e.g. Sora's `detect_and_block_ip` while it still exists) — never deepfake a real
  person without written consent.
- **Music/SFX**: license sync rights; don't pull copyrighted tracks. Use cleared libraries or
  generative audio with clear terms.
- **Generative content provenance**: 2026 models increasingly embed **C2PA Content Credentials** /
  SynthID. Preserve them; disclose AI use where the platform/jurisdiction (EU AI Act transparency)
  requires it.
- **Fonts/stock/LUTs**: confirm commercial + broadcast licenses. Brand-safety: keep generated
  backgrounds free of real logos/trademarks you don't own.

## Consistency / scale

- **Lock a look bible**: lens set, LUT/show-LUT, color script, grain profile, title system — applied
  to every shot regardless of acquisition method.
- **Style/character refs** for AI shots (reference images + pinned seeds); brand kit (logo, type,
  color tokens via `color-design-master`) for overlays.
- **Naming/versioning**: `proj_seq_shot_vNN`; one source of truth for selects; EDL/XML conform.

## QA / review

```
- [ ] Picture locked BEFORE grade/finish (no editorial changes downstream)
- [ ] Every shot hits all 4 "5D" axes (depth, form, light, motion) — no flat clips
- [ ] One focal-length logic + one lighting grammar across the cut
- [ ] Timeline fps decided once; all sources conformed (no judder)
- [ ] Color-managed grade; scopes legal for target (broadcast/ web/ HDR)
- [ ] Captions/subtitles present + correct; safe areas respected for each aspect
- [ ] Loudness normalized to spec (see delivery); no clipping
- [ ] Rights cleared: talent, music, fonts, stock, AI likeness/IP
- [ ] QC on the actual delivery file (not the timeline) on a calibrated display
```

## Delivery specs (codecs / color space / formats)

| Target | Master / codec | Color | Notes |
|--------|----------------|-------|-------|
| **Mezzanine / archive** | Apple **ProRes 422 HQ** or 4444 (alpha) | scene/Rec.709 or P3 | the file you keep + re-encode from |
| **Web/social SDR** | **H.264** high (older) / **H.265** / **AV1** | Rec.709, BT.1886 g2.4 | tag `bt709` primaries/trc/matrix |
| **HDR streaming** | H.265 / AV1, 10-bit | **Rec.2020 ST.2084 (PQ)** or HLG | carry HDR10 metadata / Dolby Vision per platform |
| **Broadcast** | per deliverable spec (often ProRes/XDCAM) | Rec.709 | legal levels (16–235), loudness **-23 LUFS EBU R128** / **-24 LKFS** US |
| **Theatrical** | DCP (JPEG2000) | **DCI-P3** | separate finishing pass |

- **Loudness** by platform: broadcast -23 LUFS (EBU R128) / -24 LKFS (ATSC A/85); most streamers/web
  ~ -14 LUFS integrated. Normalize to the target, true-peak ≤ -1 dBTP.
- **Aspect/runtime/codec** per platform → `video-social-export-specs`. **ffmpeg** post recipes →
  `video-ffmpeg-post-production`. Don't re-encode an already-compressed delivery; export from the
  ProRes master.

## Accessibility & i18n / RTL

- **Captions/subtitles**: ship SRT/VTT (web) or burned-in for social; verbatim, time-accurate,
  ≤ ~42 chars/line, 2 lines. Open captions for sound-off social feeds.
- **Contrast/legibility**: title text over video needs a scrim/shadow/plate to clear ~4.5:1 against
  the busiest frame behind it — verify against the *moving* plate, not a still.
- **i18n/RTL**: design lower-thirds/end-cards with a translation + RTL (Arabic/Hebrew) mirror in
  mind — mirror layout, right-align, use a font with full script coverage; never bake un-translatable
  text into generated footage. Provide a "max-length string" layout test.
- Avoid >3 flashes/sec (photosensitivity); provide audio description track where required.

## Anti-patterns

- Treating "5D" as a magic format/codec instead of a quality bar — and shipping flat, depthless AI clips.
- One model for every shot (pay hero rates for throwaways, or ship a draft hero).
- Grading/finishing before picture lock; compositing on already-graded plates.
- Baking text/logos into generative footage (drift, can't localize) instead of Remotion overlays.
- Mixing focal-length logic and lighting grammar shot-to-shot → it reads as "stitched-together stock".
- Faking anamorphic flares / fake film grain over an obviously digital, flat image.
- Delivering 8-bit with banding; re-encoding from an already-compressed file.

## Agent checklist

```
- [ ] Treatment + shot list + lens plan + color script exist before acquisition
- [ ] Each shot routed (live / VP / AI / 3D) with cost + fallback
- [ ] AI shots: exact model ID from live card, seeds/refs pinned, audio plan set
- [ ] Depth/parallax built into every "establishing/empty" shot (no flat plates)
- [ ] Overlays/titles in Remotion (useCurrentFrame, layout="none", gl:"angle")
- [ ] Color-managed grade; QC on delivery file; loudness + captions to spec
- [ ] Rights cleared; provenance/credentials preserved; brand-safe
```

## References (2026-current)

- fal video models: https://fal.ai/models?categories=text-to-video · fal queue/webhooks: https://fal.ai/docs
- Runway API: https://docs.dev.runwayml.com/ · Veo on Vertex: https://cloud.google.com/vertex-ai/generative-ai/docs/video/generate-videos
- Unreal Engine virtual production / ICVFX: https://dev.epicgames.com/documentation/en-us/unreal-engine/in-camera-vfx-overview
- Remotion `@remotion/three`: https://www.remotion.dev/docs/three · ThreeCanvas: https://www.remotion.dev/docs/three-canvas
- EBU R128 loudness: https://tech.ebu.ch/publications/r128 · C2PA: https://c2pa.org

## Related

`ai-video-models-selection`, `ai-video-api-fal-runway`, `ai-video-cinematic-prompts`,
`ai-image-to-video-consistency`, `remotion-programmatic-video`, `video-ffmpeg-post-production`,
`video-social-export-specs` (all in `video-ai-master`); `color-grading-cinematic`,
`3d-render-motion-graphics`, `image-5d-pro` (this master); `color-design-master`, `ui-master`.
