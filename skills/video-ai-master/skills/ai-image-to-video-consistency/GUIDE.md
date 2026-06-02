---
name: ai-image-to-video-consistency
description: >-
  Lock visual identity across AI video: image-to-video, reference-to-video (Veo image_urls), first-last-frame
  (Veo/Kling tail/Luma end), and Sora character cameos — with reference-image prep, prompt locking, and the
  Gemini-Flash-Image → Veo workflow. Use when output must match a product, logo scene, or recurring character.
---

# Image-to-Video & Visual Consistency

**Mandate:** the model has **no memory between calls** — consistency is an input you supply (reference images,
locked seed, identical character-bible sentence), not a behavior you hope for. For products and recurring
people, drive from a **reference**, never from text alone, or the face/label changes every shot.

## When to use / NOT use

- **Use** when the output must match an existing photo/product/logo or keep a character consistent across shots.
- **NOT** for free creative B-roll with no fixed subject (plain text-to-video is cheaper and freer).

## Decision matrix — mode → verified endpoint

| Mode | What it does | Verified endpoint(s) | Key inputs |
|------|--------------|----------------------|-----------|
| **Image-to-video** | animate one still | `kling-video/v2.5-turbo/pro/image-to-video`, `luma-dream-machine/ray-2/image-to-video`, `veo3.1/lite/image-to-video` | `image_url` |
| **Reference-to-video** | keep a subject's appearance from refs | `fal-ai/veo3.1/reference-to-video` | `image_urls` (list) |
| **First-last-frame** | controlled A→B transition | `fal-ai/veo3.1/first-last-frame-to-video`, Kling `tail_image_url`, Luma `end_image_url` | `first_frame_url`+`last_frame_url` / `image_url`+`tail`/`end` |
| **Character cameo** | reuse a named character | Sora 2 `character_ids` (≤2, from create-character) | `character_ids` + name in prompt |

## Reference image prep (garbage in → garbage out)

- Subject occupies **>5% of frame**, sharp focus, not occluded/cropped.
- Even, neutral lighting; avoid hard shadows that the model bakes in.
- **Same outfit + hair** in every reference for a recurring character.
- Product: clean/seamless background, standard **3/4 angle**, label legible.
- Host refs on a stable HTTPS URL (or upload via `fal_client.upload_file`) — pass the **same URL** every shot.

## Prompt + reference pattern

```text
[Exact character-bible sentence, verbatim from STORYBOARD.json]
Animate subtle natural movement: slow turn toward camera, preserve the exact face, hair, and outfit
from the reference image. 50mm, shallow depth of field, soft studio key light. No change to wardrobe.
```

The prompt describes **motion only** — the reference carries identity. Asking the prompt to also re-describe the face fights the reference and causes drift.

## First-last-frame (the most controllable mode)

```python
import fal_client
res = fal_client.subscribe("fal-ai/veo3.1/first-last-frame-to-video", arguments={
    "prompt": "Smooth dolly-in from the wide product-on-shelf shot to a tight hero close-up. "
              "Continuous motion, no cut. Audio: soft ambient retail tone.",
    "first_frame_url": "https://cdn.example.com/shelf.png",
    "last_frame_url":  "https://cdn.example.com/hero.png",
    "aspect_ratio": "9:16", "duration": "8s", "generate_audio": True,
})
url = res["video"]["url"]
```

Use cases: box → unboxed reveal, empty room → person arrived, season A → season B. The prompt describes the **transition and audio between** the two frames.

## The Gemini-Flash-Image → Veo workflow (consistent frames, then motion)

1. Generate the **first frame** with Gemini 2.5 Flash Image (Nano Banana) from a character/product reference.
2. Generate a **complementary last frame** (different POV/state) from the *same* reference → identity holds.
3. Feed both into `veo3.1/first-last-frame-to-video` → character consistency **plus** narrative control in one shot.

(Image generation itself → `documents-master` `generating-images`; this skill consumes the frames.)

## Product demo recipe

1. Shoot or generate a **hero still** (clean bg, 3/4 angle).
2. `image-to-video` with **minimal** motion: `slow 360° orbit`, `light gleam sweeps across label`, `hand enters and lifts product`.
3. Keep `cfg_scale ≈ 0.5` (Kling) so motion stays faithful to the still.
4. Add price/name/CTA as a **Remotion overlay** — never in the AI frame.

## Sora 2 character cameo (named, reusable)

```jsonc
// after create-character → character_ids; reference the character BY NAME in the prompt
{ "prompt": "Layla walks into the cafe and waves at the barista.",
  "character_ids": ["char_layla_01"], "aspect_ratio": "9:16", "duration": "8" }
```

`character_ids` forces the OpenAI provider; clear likeness rights before using a real person's cameo.

## Edge cases / gotchas

- **Front-face ref → profile prompt** drifts identity. Add an angle-appropriate reference or keep the framing.
- **Different ref URL per shot** for the "same" character = different person. One canonical URL.
- **Over-strong motion on i2v** abandons the reference — keep moves subtle (orbit/gleam/turn), not "explodes, runs, spins".
- **Mismatched first/last frame** (different lighting/scale) → warping mid-transition. Generate both from one source.
- **fal upload URLs / output URLs expire** — persist refs and results to your own bucket.

## Performance / cost

- i2v and FLF cost the same per-second as t2v on the same model — the win is **fewer rerolls** (reference removes the identity lottery).
- Generate references once; reuse across the whole storyboard. Drafting? Use `veo3.1/lite/image-to-video` or Ray-2 Flash.

## Agent checklist

```
- [ ] Recurring subject driven by a reference, not text alone
- [ ] Same canonical ref URL + verbatim bible sentence across all its shots
- [ ] Prompt describes MOTION only; reference carries identity
- [ ] First/last frames generated from one source (matched light/scale)
- [ ] Motion kept subtle on image-to-video (cfg ~0.5 on Kling)
- [ ] Likeness rights cleared for any real-person cameo
```

## Anti-patterns

- "Make it look like the same guy" in text with no reference → it won't.
- Re-describing the face in the prompt while also passing a reference → tug-of-war, drift.
- Baking product text/price into the generated frame instead of overlaying in Remotion.

## References

- Veo 3.1 reference + first-last-frame: https://fal.ai/models/fal-ai/veo3.1/first-last-frame-to-video
- Kling 2.5 i2v (`tail_image_url`): https://fal.ai/models/fal-ai/kling-video/v2.5-turbo/pro/image-to-video
- Luma Ray 2 i2v (`end_image_url`): https://fal.ai/models/fal-ai/luma-dream-machine/ray-2/image-to-video

## Related

`ai-video-cinematic-prompts`, `ai-video-storyboard-multishot`, `ai-video-models-selection`, `generating-images` (documents-master)
