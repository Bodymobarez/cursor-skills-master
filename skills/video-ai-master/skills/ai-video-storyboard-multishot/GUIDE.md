---
name: ai-video-storyboard-multishot
description: >-
  Design multi-shot AI videos as a machine-readable shot list: narrative arcs, 2–8s clip budgeting,
  per-shot model/seed/ref, transition planning (cut/match/dissolve), character bible for continuity,
  and a STORYBOARD.json that drives batch generation + ffmpeg assembly. Use before generating clips.
---

# AI Video Storyboard & Multi-Shot

**Mandate:** generative models are **short-clip engines** — design for assembly, not for one long take.
The storyboard is a typed artifact (`STORYBOARD.json`) that the generation script, the assembler, and QA all
read. If your "storyboard" is prose in a chat, you cannot batch-generate, diff a client note, or reproduce a render.

## When to use / NOT use

- **Use** to convert an approved script into a shot list with model, duration, ref, and seed per shot.
- **NOT** for a single clip (skip straight to prompts/API). The ceremony pays off at ≥3 shots.

## Mental model

```
script beats ──▶ shots (1 idea, 1 action, 2–8s each) ──▶ STORYBOARD.json
                                   │                          │
              transitions planned in EDIT (not in prompts) ───┘──▶ generate → assemble → QA
```

Coherence comes from **constraints repeated across shots** (character bible, lighting words, aspect, fps), not
from the model "remembering". The model remembers nothing between calls — you supply continuity.

## STORYBOARD.json (the deliverable)

```jsonc
{
  "project": "service-launch", "fps": 30, "master_aspect": "9:16", "resolution": "1080p",
  "character_bible": {
    "host": "Emirati man, early 30s, trimmed beige kandura, short dark beard, warm key light camera-left"
  },
  "shots": [
    { "id": "01_hook",    "beat": "hook",     "dur_s": 3, "model": "fal-ai/veo3.1",
      "prompt_ref": "prompts/01.txt", "ref_image": null,          "audio": true,  "seed": 4412, "status": "approved" },
    { "id": "02_problem", "beat": "problem",  "dur_s": 4, "model": "fal-ai/kling-video/v2.5-turbo/pro/image-to-video",
      "prompt_ref": "prompts/02.txt", "ref_image": "refs/desk.png","audio": false, "seed": 7781, "status": "pending"  },
    { "id": "03_solution","beat": "solution", "dur_s": 4, "model": "fal-ai/veo3.1/first-last-frame-to-video",
      "prompt_ref": "prompts/03.txt", "first_frame": "refs/app_a.png", "last_frame": "refs/app_b.png", "audio": false, "seed": 3120, "status": "pending" },
    { "id": "04_cta",     "beat": "cta",      "dur_s": 3, "model": "remotion",
      "props": { "title": "ابدأ اليوم", "logo": "brand/logo.svg" }, "audio": "music" }
  ]
}
```

## Narrative arcs (pick one, then fill shots)

| Format | Structure | Shots |
|--------|-----------|-------|
| 15s ad | Hook → 1 benefit → CTA | 3–5 |
| 30s ad | Hook → problem → solution → proof → CTA | 5–7 |
| 60s explainer | Hook → 3 beats → recap → CTA | 8–12 |
| UGC | selfie hook → demo → social proof → CTA | 4–6 |
| Product reveal | tease → first-last-frame unbox → hero spin → CTA | 4–6 |

## Clip-length budgeting

| Platform | Total | Shots | Per shot |
|----------|-------|-------|----------|
| TikTok | 15–34s | 4–7 | 2–6s |
| Reels | 15–90s | 5–12 | 3–6s |
| Shorts | ≤60s | 4–10 | 3–6s |
| YouTube pre-roll | 6 / 15 / 30s | strict | hook in 0–2s |

Hero/dialogue shots earn 5–8s; cutaways and B-roll stay 2–4s. Longer ≠ better — long generations drift.

## Transitions (plan in EDIT, never inside a prompt)

| Transition | When | How |
|-----------|------|-----|
| Hard cut | most social, fast pacing | ffmpeg concat (default) |
| Match cut | same motion direction/shape across shots | align action vector at shot edges |
| Cross-dissolve 6–12f | emotional / time passage | Remotion `<TransitionSeries>` fade, or ffmpeg `xfade` |
| Whip/wipe | energetic transitions | Remotion `@remotion/transitions` wipe |
| First-last-frame morph | *intentional* A→B within one shot | Veo FLF / Kling `tail_image_url` |

Never rely on a model to "morph between unrelated scenes" — it hallucinates. Generate discrete shots, transition deterministically in Remotion/ffmpeg.

## Character & product continuity bible

```markdown
## Host (recurring)
- Fixed sentence (paste verbatim into EVERY prompt): "Emirati man, early 30s, beige kandura, short dark beard"
- Lighting: warm key camera-left, soft fill
- Reference: refs/host.png (same URL every shot)

## Product
- 3/4 angle, clean white sweep, same gloss/label
- Reference: refs/bottle.png
```

Lock wardrobe + hair + lighting + ref URL across shots. See `ai-image-to-video-consistency` for ref prep and modes.

## Drive generation from the storyboard

```python
import json, fal_client
sb = json.load(open("STORYBOARD.json"))
for shot in sb["shots"]:
    if shot["model"] == "remotion" or shot["status"] == "approved":
        continue  # code shots + already-approved shots are skipped (idempotent)
    args = {"prompt": open(shot["prompt_ref"]).read(),
            "aspect_ratio": sb["master_aspect"], "resolution": sb["resolution"], "seed": shot["seed"]}
    if shot.get("ref_image"):  args["image_url"] = upload(shot["ref_image"])
    res = fal_client.subscribe(shot["model"], arguments=args)
    download(res["video"]["url"], f"shots/raw/{shot['id']}.mp4")
```

Re-running only regenerates `pending` shots — approved shots and their seeds are untouched. That is the whole point of the artifact.

## Assembly order (`shots.txt` for ffmpeg)

```
file 'shots/norm/01_hook.mp4'
file 'shots/norm/02_problem.mp4'
file 'shots/norm/03_solution.mp4'
file 'shots/norm/04_cta.mp4'
```

Normalize all clips to identical fps/codec/resolution **before** concat (see `video-ffmpeg-post-production`), or the concat demuxer fails or stutters.

## Edge cases / gotchas

- **Mixed fps/resolution** across models → concat artifacts. Normalize to the storyboard's `fps`/`resolution` first.
- **Aspect drift** — one shot generated 16:9 in a 9:16 project = letterbox or crop loss. Enforce `master_aspect` in the loop.
- **Seedless reruns** quietly change approved shots. Persist seeds; treat `status:"approved"` as immutable.
- **Over-long arcs** — if a 15s ad has 10 shots, cuts feel frantic. Match shot count to the table.

## Agent checklist

```
- [ ] One narrative arc chosen; one idea + one action per shot
- [ ] STORYBOARD.json typed: model, dur_s, seed, ref, audio, status per shot
- [ ] Character/product bible sentence reused verbatim across recurring shots
- [ ] Transitions assigned to EDIT (cut/dissolve/FLF), not to prompts
- [ ] All shots share master_aspect + fps + resolution
- [ ] Generation loop is idempotent (skips approved, keyed by seed)
```

## Anti-patterns

- Prose-only storyboard → no batch, no diff, no reproducibility.
- "The model will keep the character consistent" → it won't; supply refs + bible every shot.
- Asking one 30s generation to tell the whole story → decompose into beats.

## References

- Veo 3.1 first-last-frame workflow: https://cloud.google.com/blog/products/ai-machine-learning/ultimate-prompting-guide-for-veo-3-1
- ffmpeg concat demuxer: https://trac.ffmpeg.org/wiki/Concatenate

## Related

`ai-video-cinematic-prompts`, `ai-image-to-video-consistency`, `video-ffmpeg-post-production`, `remotion-programmatic-video`
