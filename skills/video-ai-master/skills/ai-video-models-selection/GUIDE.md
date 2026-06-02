---
name: ai-video-models-selection
description: >-
  Pick the right AI video model PER SHOT (2026): Veo 3.1, Kling 2.5 Turbo Pro, Runway Gen-4.5/Turbo/Aleph,
  Sora 2 (Pro), Luma Ray 2, Pika 2.2, Wan 2.2 — with verified fal.ai/Runway endpoints, real input params,
  native-audio support, per-second cost, and a fallback chain. Use before generating anything.
---

# AI Video Model Selection (2026)

**Mandate:** there is no single best model — route **per shot** on four axes: motion realism, native audio,
controllability (refs/first-last-frame), and $/second. Wrong routing means either burning hero-tier money on
throwaway drafts or shipping a draft-tier hero shot. **Verify the model card before production — params drift.**

> Correction worth internalizing: the current flagship Kling on fal is **`v2.5-turbo/pro`**, not "Kling 3".
> Inventing version strings 404s in prod. Always copy the exact `Model ID` from the fal model card.

## When to use / NOT use

- **Use** to choose model + tier + fallback for each storyboard row before writing prompts.
- **NOT** for exact branded text/charts/legal (that's `remotion-programmatic-video`) or talking-head presenters
  (`ai-avatar-presenter-video`). Those are not generative-diffusion problems.

## Decision matrix — pick by job

| Need | Model (verified ID) | Native audio | Notes |
|------|---------------------|:---:|------|
| Best prompt adherence + **dialogue/SFX in one shot** | **Veo 3.1** `fal-ai/veo3.1` | ✅ | 4/6/8s, up to 4k, `generate_audio` |
| Narrative + lip-synced dialogue, cameo characters | **Sora 2 Pro** `fal-ai/sora-2/text-to-video/pro` | ✅ | 4–20s, `character_ids` (≤2) |
| Fluid cinematic motion, volume/cost, **first-last-frame** | **Kling 2.5 Turbo Pro** `fal-ai/kling-video/v2.5-turbo/pro/*` | ❌ | 5/10s, `tail_image_url` |
| Editor-grade control, video-to-video, act transfer | **Runway Gen-4.5 / Aleph** (`gen4.5`,`gen4_aleph`) | ✅(4.5) | `api.dev.runwayml.com` |
| Fast, cheap, looping social B-roll | **Luma Ray 2 (Flash)** `fal-ai/luma-dream-machine/ray-2[-flash]` | ❌ | `loop`, 540p default |
| Stylized creative effects, two-stage quality | **Pika 2.2** `fal-ai/pika/v2.2/*` | ❌ | t2i→i2v, 5/10s |
| Cheapest iteration / open-weights / fine control | **Wan 2.2 A14B** `fal-ai/wan/v2.2-a14b/*` | ❌ | `num_frames`, `fps`, `guidance_scale` |
| Exact text / charts / 500 variants | **Remotion** (code) | n/a | not generative — see remotion skill |
| Script → presenter | **HeyGen / Synthesia** | ✅ | see avatar skill |

## Verified input params (fal.ai — copy exactly)

| Model | Endpoint ID | Key params (defaults) |
|-------|-------------|-----------------------|
| Veo 3.1 | `fal-ai/veo3.1` | `aspect_ratio` 16:9\|9:16 (16:9), `duration` 4s\|6s\|8s (8s), `resolution` 720p\|1080p\|4k (720p), `generate_audio` (true), `negative_prompt`, `seed`, `auto_fix` (true), `safety_tolerance` 1–6 (4) |
| Veo 3.1 FLF | `fal-ai/veo3.1/first-last-frame-to-video` | + `first_frame_url`, `last_frame_url` (required) |
| Veo 3.1 refs | `fal-ai/veo3.1/reference-to-video` | + `image_urls` (list, subject consistency) |
| Veo 3.1 cheap | `fal-ai/veo3.1/fast`, `fal-ai/veo3.1/lite` | same schema, lower cost/latency |
| Kling 2.5 | `fal-ai/kling-video/v2.5-turbo/pro/text-to-video` | `duration` 5\|10 (5), `aspect_ratio` 16:9\|9:16\|1:1 (16:9), `cfg_scale` 0–1 (0.5), `negative_prompt` |
| Kling 2.5 i2v | `…/v2.5-turbo/pro/image-to-video` | + `image_url` (req), `tail_image_url` (end frame) |
| Sora 2 | `fal-ai/sora-2/text-to-video[/pro]` | `resolution` 720p\|1080p\|true_1080p, `aspect_ratio` 9:16\|16:9, `duration` 4\|8\|12\|16\|20 (4), `delete_video` (true), `character_ids`, `detect_and_block_ip` |
| Luma Ray 2 | `fal-ai/luma-dream-machine/ray-2[/image-to-video]` | `aspect_ratio` (16:9), `loop`, `resolution` 540p\|720p\|1080p (540p), `duration` 5s\|9s (5s), i2v: `image_url`,`end_image_url` |
| Pika 2.2 | `fal-ai/pika/v2.2/text-to-video` | `aspect_ratio`, `resolution` (720p), `duration` 5s\|10s, `negative_prompt`, `seed` |
| Wan 2.2 | `fal-ai/wan/v2.2-a14b/text-to-video` | `resolution` 480p\|580p\|720p, `num_frames` 17–161, `frames_per_second` 4–60, `guidance_scale`, `shift` |

## Runway (direct API, not fal)

`POST https://api.dev.runwayml.com/v1/image_to_video` · header `X-Runway-Version: 2024-11-06` · `Authorization: Bearer $RUNWAYML_API_SECRET`

| `model` | Use | Credits/s ($0.01/credit) |
|---------|-----|--------------------------|
| `gen4.5` | newest, best quality, text-or-image-to-video | 12 |
| `gen4_turbo` | 7× faster, high-volume | 5 |
| `gen4_aleph` | video-to-video editing / restyle | 15 |
| `act_two` | performance/expression transfer | 5 |

Body: `promptText` (≤1000 chars; omit `promptImage` for text-to-video), `promptImage`, `ratio` (e.g. `"1280:720"`), `duration` 5\|10. Poll `client.tasks.retrieve(id)` until `SUCCEEDED`.

## Cost mental model

- fal bills **per second of output**; audio, 1080p/4k, and Pro tiers cost more. Budget at the *shot* level.
- Rule of thumb (verify live): draft tiers (`fast`/`lite`/Wan) are ~3–8× cheaper than hero (Veo 4k+audio, Sora Pro).
- 30s ad @ 6 shots × 5s = **6 metered calls**. One 30s call (where even possible) is more expensive *and* less coherent.
- Log `model, duration_s, resolution, audio, est_usd` per job (see `ai-video-api-fal-runway` cost logging).

## Gateway + fallback strategy

```ts
// One integration shape; model is config, not code. A/B = swap one string.
const ROUTING = {
  hero:   "fal-ai/veo3.1",
  motion: "fal-ai/kling-video/v2.5-turbo/pro/text-to-video",
  draft:  "fal-ai/wan/v2.2-a14b/text-to-video",
} as const;
const FALLBACK = ["fal-ai/veo3.1", "fal-ai/kling-video/v2.5-turbo/pro/text-to-video", "fal-ai/wan/v2.2-a14b/text-to-video"];
```

Keep **2 fallbacks** wired and capability-aware: if you fall back off Veo you lose native audio → generate audio separately (`ai-video-audio-voiceover`).

## Per-shot assignment example (30s ad)

| Shot | Model | Why |
|------|-------|-----|
| Establishing wide + ambience | `fal-ai/veo3.1` (audio on) | cinematic + native ambient sound |
| Product close-up from photo | `kling-video/v2.5-turbo/pro/image-to-video` | ref image, fluid motion, cheaper |
| Box → unboxed reveal | `veo3.1/first-last-frame-to-video` | controlled start/end transition |
| Founder line to camera | HeyGen / Sora 2 (`character_ids`) | lip-sync to script |
| End card (logo + price + CTA) | Remotion | crisp text, brand color |

## Edge cases / gotchas

- **Audio expectation mismatch:** Kling/Luma/Pika/Wan are silent — plan a VO/music pass or you'll ship muted hero shots.
- **Aspect support varies:** Kling adds `1:1`; Sora is `9:16`/`16:9` only. Don't request an unsupported ratio.
- **`delete_video:true` (Sora default)** permanently deletes server-side and blocks remix — download immediately and set `false` if you need the asset later.
- **Runway `ratio` is pixel dims** (`"1280:720"`), not `"16:9"`. fal uses semantic ratios.
- **Snapshots drift:** pin Sora `model: "sora-2-2025-12-08"` for reproducible client work instead of the moving `sora-2`.

## Agent checklist

```
- [ ] Each storyboard row has model + tier + 2 fallbacks
- [ ] Exact Model ID copied from the live fal/Runway card (no invented versions)
- [ ] Audio plan exists for any silent-model shot
- [ ] Aspect ratio is in the model's supported set
- [ ] Draft on cheap tier; promote only approved shots to hero
- [ ] est_usd per shot summed against the budget ceiling
```

## References

- fal video gallery: https://fal.ai/models?categories=text-to-video
- Veo 3.1 on fal: https://fal.ai/models/fal-ai/veo3.1 · Kling 2.5: https://fal.ai/models/fal-ai/kling-video/v2.5-turbo/pro/text-to-video
- Sora 2: https://fal.ai/models/fal-ai/sora-2/text-to-video/pro · Runway API: https://docs.dev.runwayml.com/

## Related

`ai-video-api-fal-runway`, `ai-video-cinematic-prompts`, `ai-image-to-video-consistency`, `ai-avatar-presenter-video`
