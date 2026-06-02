---
name: image-5d-pro
description: >-
  Create premium photoreal & 3D-render images at principal depth: structured AI prompt craft
  (subject · lighting · lens · material · depth/atmosphere), composition & lensing, model routing
  (Midjourney V8 / Flux 2 / GPT-Image / Nano Banana 2 / Ideogram), reference-based consistency,
  real upscaling (Topaz / Magnific), retouch, and wide-gamut / Display-P3 export. "5D" = photoreal
  depth + 3D form + cinematic light + (implied) motion — a quality bar, not a format.
---

# Image 5D Pro

## Mandate

Generate or art-direct **single frames that look photographed or rendered by a pro** — correct
lensing, motivated light, real materials, and genuine depth. The deliverable is a *believable image
with a point of view*, not "an AI picture".

**"5D" is a quality bar, not a format.** A 5D image stacks the same four real axes the rest of this
master uses: **photoreal depth** (atmosphere, occlusion, falloff), **3D form** (volume from light +
lens, not flat stickers), **cinematic lighting** (motivated, directional, color-temperature intent),
and **implied motion** (gesture, drift, a frame that feels like a moment, not a pose). Miss one and
you have a flat render. No "5D file format" exists — don't imply one.

## When to use / NOT use

- **Use** for hero/key art, ad stills, product imagery, editorial illustration, environment concepts,
  textures/matte plates, and any reference frame feeding `cinematic-5d-video-production` or
  `image-to-video`.
- **NOT** for: logos/marks (→ `logo-5d-pro` — vector, not raster), data viz/charts (code, not
  diffusion), or palette/contrast systems (→ `color-design-master`). For 3D *scenes* you'll
  re-render/animate, build them in `3d-render-motion-graphics` and export frames.

## Mental model — the 5-block prompt + the production loop

Photoreal generation is **art direction in text**. Every strong prompt names five blocks, in order
of impact:

```
SUBJECT      what + state/gesture + wardrobe/material specifics (concrete nouns beat adjectives)
LIGHTING     key direction/quality/ratio · time of day · color temp · practicals · mood
LENS/CAMERA  focal length · aperture/DOF · angle/height · format (e.g. "85mm, f/1.8, eye-level")
MATERIAL     surface microdetail: skin pores, brushed metal, woven fabric, condensation, dust
DEPTH/ATMOS  fg/mid/bg layering · haze/volumetrics · bokeh · atmospheric perspective
```

The loop: **concept → route model → batch low-res explorations (seeds) → select → refine/inpaint →
upscale → retouch → color-manage → export**. Don't upscale or retouch before the composition is right.

## Model routing — pick by job (2026, verify the live model card)

| Need | Model | Why | Watch |
|------|-------|-----|-------|
| **Cinematic aesthetic / art direction** | **Midjourney V8 (V7)** | unmatched dramatic comp + light; `--hd` native 2K, better text | weak on exact instructions; web/Discord |
| **Photoreal + anatomy + camera realism** | **Flux 2** (Pro / Klein / Schnell) | skin/fabric/material fidelity; open weights → LoRA | self-host or fal; Schnell = fast drafts |
| **Best instruction-following + multi-subject** | **GPT-Image (1.5 / 2)** | top arena Elo, follows complex prompts, decent text | ~1536px long edge → upscale for print |
| **Native 4K, refs, fast iteration** | **Nano Banana 2** (Gemini 3.x Flash Image) | up to 4K, **up to 14 reference images**, search-grounded, SynthID+C2PA | newest — verify availability/region |
| **Legible styled text in image** | **Ideogram 3.0** | purpose-built for in-image typography | not for photoreal hero |
| **Full local control / IP-sensitive** | **Stable Diffusion 3.5 / Flux Klein** | open weights, LoRA, on-prem, no per-image cost | needs GPU + pipeline craft |

Most pros run **two**: an aesthetic model (Midjourney) + a controllable/photoreal one (Flux 2) or a
text/instruction one (GPT-Image). Route via **fal.ai** to keep one integration (same auth/queue/cost
pattern as `ai-video-api-fal-runway`); keep keys server-side.

## Composition & lensing (the difference between "render" and "photograph")

- **Frame intentionally**: rule-of-thirds/golden ratio as a *start*; then leading lines, negative
  space, foreground occluders for depth, and a clear focal hierarchy (one hero, supporting elements
  subordinate).
- **Pick a focal length on purpose** (same language as the video skill): 24–35mm environmental,
  40–50mm natural, 85mm portrait/isolation, 135mm compressed. State it in the prompt — it changes
  perspective, not just FOV.
- **Light with ratios**: name key + fill + rim, a key:fill ratio (e.g. 4:1 for drama), and color temp
  (warm key / cool fill). "Cinematic lighting" alone is noise; "hard key camera-left 45°, cool window
  fill, amber practical rim, 4:1" is direction.
- **Lens artifacts in moderation**: shallow DOF, gentle bokeh, subtle chromatic aberration/halation,
  and a touch of grain sell "captured". Overdone = video-game cutscene.

## Production prompt assets (copy/paste, then tune per model)

Photoreal product hero (Flux 2 / Nano Banana):

```text
Subject: a matte-black titanium wristwatch on wet basalt, sapphire crystal catching a thin highlight.
Lighting: single hard key camera-left at 45°, soft cool fill from a window, warm practical rim behind;
  key:fill ~5:1, late-afternoon mood.
Lens: 100mm macro equivalent, f/4, slight top-down 20°, full-frame.
Material: brushed titanium micro-grain, anti-reflective coating, micro water droplets, fine dust on slate.
Depth: shallow DOF, creamy background falloff into shadow, faint volumetric haze for separation.
Style: editorial product photography, photoreal, neutral-accurate color.
Negative: text, logos, watermark, plastic look, oversaturation, extra hands.
--ar 4:5  (Midjourney) / aspect_ratio "4:5" (fal)   seed: 7321
```

Cinematic environment / key art (Midjourney V8):

```text
A lone figure on a rain-slick neon street in a dense future city, seen from behind, 35mm, f/2,
eye-level, volumetric fog, wet reflections doubling the neon, teal shadows / magenta highlights,
strong atmospheric perspective into haze, cinematic, photoreal --ar 21:9 --hd --style raw
```

3D-render look (when you want CG cleanliness, not photography):

```text
Studio 3D render, octane/redshift look, soft HDRI key + gradient backdrop, subsurface-scattering on
a glossy ceramic form, sharp PBR reflections, shallow DOF, 50mm, neutral gray seamless, product-viz.
```

## Reference-based consistency (the part that scales)

A one-off hero is easy; a *campaign* needs the same subject/style across 30 images.

- **Pin the seed** + keep prompt blocks identical; vary only what must change.
- **Reference/IP-adapter / character refs**: Nano Banana 2 takes up to 14 refs (10 object + 4
  character); Midjourney `--cref`/`--sref` (character/style refs); Flux 2 via reference inputs/LoRA.
- **Train a LoRA** (Flux 2 / SD 3.5) on a product or face for true brand consistency at volume.
- **Style frame first**: lock one approved "look" image, then drive the rest from it as a style ref.
- **Batch + log**: generate sets, record `model, seed, prompt_hash, ref_ids` so any frame is
  reproducible.

## Upscaling — real tools, right tool

| Tool | What it does | Use when | Don't |
|------|--------------|----------|-------|
| **Topaz Photo AI / Gigapixel** | *fidelity* restore — recovers/sharpens without changing identity; local, perpetual ~$199 | photos, faces, anything where the subject must stay true | expect it to invent missing detail |
| **Magnific AI** | *generative* reconstruction — hallucinates plausible high-freq detail (pores, weave); cloud SaaS | upscaling AI art to print res, adding texture/grit | client likeness/forensic accuracy |
| **Native model upscale** (MJ 2x, Flux/Recraft up-res) | in-pipeline bump | quick 2x within the same look | large-factor print enlargements |
| **Real-ESRGAN / SUPIR (open)** | self-hosted upscale | on-prem/IP-sensitive volume | turnkey simplicity |

Rule: **Topaz when truth matters, Magnific when *impression* matters.** Upscale *after* composition
is locked and *before* final retouch/color.

## Retouch & finishing

- **Non-destructive**: layers/masks (Photoshop, Affinity, or GIMP); keep the generation + each step.
- **Inpainting/generative fill** to fix hands, remove artifacts, extend canvas (out-paint) — but
  re-check seams at 100%.
- **Dodge & burn / frequency separation** for skin; **clone/heal** for blemishes; **curves** for
  contrast — all the real photo-retouch craft applies to AI frames too.
- **Grain + subtle defocus** unify composited elements and kill the "too clean" AI tell.
- Keep a **calibrated display** (hardware-calibrated, known white point) or you're retouching blind.

## Edge cases / gotchas

- **Hands / text / symmetry**: still the weak spots — inpaint hands, add text in vector/DOM later,
  verify logos aren't hallucinated.
- **Over-saturation & "HDR sheen"**: models love crunchy contrast; pull back to believable.
- **Same-face syndrome**: default model faces repeat — use refs/LoRA for distinct people.
- **Aspect baked wrong**: generate at the delivery aspect; don't crop a square into a banner.
- **8-bit banding** in skies/gradients → request/export higher bit depth; add dither.
- **Metadata loss**: exports can strip color profile + C2PA — embed both on purpose (below).

## Performance / cost

- **Draft cheap, finish expensive**: explore on Schnell/fast/low-res with many seeds; only upscale +
  retouch the 1–2 selects. Log `model, seed, $/image`; track **$ per *delivered* asset** (incl.
  rejects).
- Batch via fal queue for volume; cache; dedupe by `prompt_hash+seed`.
- Self-host (SD 3.5 / Flux Klein) when per-image cost × volume beats GPU rental.
- Upscaling is the heavy step — only run it on approved frames.

## Rights / licensing / likeness & brand safety

- **Commercial license**: confirm each model's terms allow commercial + the resolution tier you ship
  (some free tiers don't). Midjourney commercial needs a paid plan, etc.
- **Likeness**: don't generate real, identifiable people without consent; avoid trademarked
  logos/characters you don't own; watch celebrity/style-of-living-artist prompts.
- **Provenance**: Nano Banana/Gemini embed **SynthID + C2PA Content Credentials** — preserve them;
  disclose AI generation where required (EU AI Act / platform rules).
- **Training-data risk**: for IP-sensitive clients prefer models with clean/commercial-safe training
  claims (e.g. some Adobe Firefly/enterprise tiers) or self-hosted with your own data.

## Consistency / scale

- **Style bible**: one approved look image + locked prompt blocks + seed/ref strategy + LUT/color
  treatment, applied across the set.
- **Brand color**: pull exact brand values from `color-design-master` tokens; don't eyeball hex.
- **Naming/versioning**: `campaign_concept_seedNNNN_vNN`; keep generation logs for reproducibility.

## QA / review

```
- [ ] All 4 "5D" axes present (depth, form, light, implied motion) — not flat
- [ ] Hands/text/symmetry checked at 100%; no hallucinated logos
- [ ] Lighting is motivated + consistent across the set; color believable (not crunchy)
- [ ] Upscaled with the right tool AFTER composition lock; seams clean
- [ ] Exported in correct color space + bit depth; profile embedded; no banding
- [ ] Rights cleared (commercial tier, likeness, IP); provenance preserved
- [ ] Reviewed on a calibrated display, at delivery size
```

## Delivery specs (color space / bit depth / DPI / formats)

| Target | Format | Color space | Bit / DPI |
|--------|--------|-------------|-----------|
| **Web (modern)** | **AVIF** / WebP / JPEG | **sRGB** (tag it) or **Display-P3** for wide-gamut | 8-bit; export @1x/2x |
| **Wide-gamut web** | PNG/AVIF with **Display-P3** ICC | Display-P3 | tag profile or Safari/Chrome show dull/oversat |
| **Print** | TIFF / PDF-X | **CMYK** (job profile, e.g. FOGRA/GRACoL) or Adobe RGB master | 16-bit master → 8-bit out; **300 DPI** at final size |
| **Large-format / billboard** | TIFF/PDF | as printer specifies | lower DPI OK at distance (e.g. 100–150) |
| **Master/archive** | 16-bit TIFF/PSD or EXR (HDR) | ProPhoto/Adobe RGB or scene-linear | keep layered + flat |

- **Display-P3**: deliver wide-gamut only with the **ICC profile embedded** and `<img>`/CSS in a
  color-managed context; provide an sRGB fallback. Untagged P3 renders wrong.
- **DPI is meaningless without physical size** — 300 DPI *at the printed dimensions*. Generate/upscale
  to the pixel count the size demands (e.g. A4 @300 ≈ 2480×3508).

## Accessibility & i18n / RTL

- **Alt text / captions** for every delivered image (describe content + function); decorative-only →
  empty alt.
- **Contrast**: any text *baked into* the image must clear WCAG (≈4.5:1 body) against its local
  background — verify with `color-design-master`/`wcag-contrast-color-pairs`. Prefer overlaying text
  in HTML/vector so it's themable and translatable.
- **i18n/RTL**: don't bake translatable copy into the raster; leave room and mirror layouts for
  Arabic/Hebrew; ensure any in-image script uses a font with full coverage.

## Anti-patterns

- Treating "5D" as a format/codec instead of a quality bar; shipping flat, depthless renders.
- Adjective-soup prompts ("ultra detailed, 8k, masterpiece, trending") instead of the 5 concrete blocks.
- Upscaling/retouching before composition is locked; large enlargement with the wrong upscaler.
- Baking brand text/logos into generations (drift, can't localize) — overlay them instead.
- Shipping untagged Display-P3 (looks broken) or 8-bit gradients that band.
- Reusing the same default model face across "different" people; ignoring likeness/IP rights.

## Agent checklist

```
- [ ] Prompt names SUBJECT · LIGHTING · LENS · MATERIAL · DEPTH (+ negatives)
- [ ] Model routed to the job; key server-side; seed/refs pinned for consistency
- [ ] Drafted cheap; only selects upscaled (right tool) + retouched
- [ ] Color space + bit depth + DPI correct for target; profile embedded
- [ ] Rights cleared; provenance (C2PA/SynthID) preserved; alt text written
- [ ] Reviewed on calibrated display at delivery size
```

## References (2026-current)

- fal image models: https://fal.ai/models?categories=text-to-image
- Flux (Black Forest Labs): https://bfl.ai/ · Midjourney docs: https://docs.midjourney.com/
- Nano Banana 2 / Gemini image: https://blog.google/innovation-and-ai/technology/ai/nano-banana-2/
- Topaz: https://www.topazlabs.com/ · Magnific: https://magnific.ai/ · C2PA: https://c2pa.org
- Display-P3 / color management: https://webkit.org/blog/10042/wide-gamut-color-in-css-with-display-p3/

## Related

`logo-5d-pro`, `3d-render-motion-graphics`, `cinematic-5d-video-production`, `color-grading-cinematic`
(this master); `color-design-master`, `ui-master`; `ai-image-to-video-consistency`,
`ai-video-api-fal-runway` (video-ai-master).
