---
name: video-ai-production-workflow
description: >-
  Staff-level orchestration for AI video: brief → script → storyboard → per-shot model routing →
  generation (fal/Runway) → Remotion overlays → ffmpeg post → multi-platform export. Owns the
  artifact contract, cost ceiling, fallback policy, reproducibility, and rights/compliance gates.
  Use as the FIRST skill for any create/generate/edit video request.
---

# AI Video Production Workflow

**Mandate:** never generate a single clip until the brief, aspect ratio, shot list, and cost ceiling
are written down. A video project is a **pipeline of short deterministic stages**, not one magic prompt.
The expensive failure mode is rendering 30 clips against the wrong aspect ratio or an unapproved script.

## When to use / NOT use

- **Use** to plan and drive the whole pipeline, assign work to the other skills, and own deliverables.
- **NOT** for a single isolated task (just one clip → `ai-video-api-fal-runway`; just captions →
  `video-ffmpeg-post-production`). Don't run the full ceremony for a 1-shot throwaway.

## Mental model — a DAG of cheap, reversible stages

```
brief ─▶ script ─▶ storyboard ─▶ [per shot: model → prompt → generate → QA] ─▶ assemble ─▶ post ─▶ export
   │         │          │                    │  ▲ retry loop (seed+prompt cached)        │
   └ specs   └ hook<2s   └ artifact: STORYBOARD.json (single source of truth) ───────────┘
```

Each stage emits a file. Re-running a stage must be **idempotent** given the same inputs (cache seed +
prompt + model id). If a stage isn't reproducible, you cannot iterate on a client note without a full reburn.

## 0. Brief (capture before anything)

| Field | Example | Drives |
|-------|---------|--------|
| Goal / KPI | TikTok ad, 3% CTR | script + hook |
| Platform(s) | Reels 9:16 + YouTube 16:9 | aspect, length, safe zones |
| Length | 15 / 30 / 60s | shot count |
| Language | Arabic VO + EN burned captions | TTS, RTL, dub |
| Brand | logo, OKLCH palette, tone | Remotion overlays |
| Likeness/rights | real CEO? stock music? | compliance gate |
| **Budget ceiling** | ≤ $4.00/render, ≤ $120 total | model routing |

## 1. Pipeline (each step → owning skill)

```
1. Platform specs + safe zones .......... video-social-export-specs
2. Script: Hook(0–2s) → Body(1 idea/shot) → CTA
3. STORYBOARD.json shot list ............ ai-video-storyboard-multishot
4. Model per shot (quality × $ × audio) . ai-video-models-selection
5. Prompts (5-part formula, neg prompts)  ai-video-cinematic-prompts
6. Consistency (refs, FLF, character) ... ai-image-to-video-consistency
7. Generate (queue, retries, cost log) .. ai-video-api-fal-runway
8. Voiceover / music / dub .............. ai-video-audio-voiceover
9. Overlays: logo, price, CTA, captions . remotion-programmatic-video
10. Avatar segments (if presenter) ...... ai-avatar-presenter-video
11. Assemble + loudnorm + burn subs ..... video-ffmpeg-post-production
12. QA gate (A/V sync, artifacts, brand)  ai-video-qa-evaluation
13. Export variants per platform ........ video-social-export-specs
```

## 2. Hybrid is the professional default

| Layer | Tool | Why |
|-------|------|-----|
| B-roll / cinematic / lifestyle | Veo 3.1 / Kling / Sora | photoreal motion, no readable text |
| Logo, price, legal, CTA, captions | **Remotion** (code) | subpixel-crisp text, exact brand color, infinite variants |
| Voice / music / SFX | ElevenLabs | controllable, licensable, localizable |

Never ask a diffusion model to render legible text/prices — it warps and is un-rethemable. Generate
the *scene* with AI, composite *text* in Remotion (`<OffthreadVideo>` + absolute-positioned brand layer).

## 3. The artifact contract (`STORYBOARD.json`)

```jsonc
{
  "project": "ramadan-promo",
  "fps": 30, "master_aspect": "9:16", "resolution": "1080p",
  "budget_usd_cap": 120,
  "shots": [
    { "id": "01_hook", "dur_s": 3, "model": "fal-ai/veo3.1", "seed": 4412,
      "prompt_ref": "prompts/01.txt", "ref_image": null, "audio": true, "status": "approved" },
    { "id": "02_product", "dur_s": 4, "model": "fal-ai/kling-video/v2.5-turbo/pro/image-to-video",
      "seed": 9001, "ref_image": "refs/bottle.png", "audio": false, "status": "pending" }
  ]
}
```

This file is the single source of truth: the generation script reads it, the assembler reads it, and a
git diff on it *is* the change log. Cache `{model, prompt, seed}` so a re-render of shot 02 never touches shot 01.

## 4. Cost control (decisions, not vibes)

| Lever | Rule |
|-------|------|
| Draft tier | iterate on Wan 2.2 / `*/fast` / `*/lite`, promote ONLY approved shots to hero tier |
| Shot length | cap 2–8s; assemble in edit — a 30s ad is 6×5s calls, never one 30s call |
| Audio | `generate_audio:false` when the shot is muted B-roll (Veo bills audio extra) |
| Seed reuse | lock seed before client review so notes = prompt tweaks, not lottery rerolls |
| Hard ceiling | sum estimated $ from cost log; **abort batch** if projected > `budget_usd_cap` |

## 5. Reliability & scale (batch)

- Generate via the **queue** (`fal.queue.submit` + webhook), not blocking calls — see `ai-video-api-fal-runway`.
- Per shot: max 3 retries with exponential backoff; on content-policy fail, `auto_fix` then soften prompt.
- Always configure **2 fallback models** (`Veo 3.1 → Kling 2.5 → Wan 2.2`). One vendor outage must not block delivery.
- Idempotency key = `{project}:{shot_id}:{seed}`; dedupe so a retried webhook never double-bills.

## 6. Deliverables (definition of done)

```
STORYBOARD.json            # source of truth + seeds (reproducible)
PROMPTS/                   # one file per shot
shots/raw/01.mp4 …         # ungraded AI clips
shots/norm/01.mp4 …        # CFR 30, H.264/AAC, normalized
final_9x16.mp4  final_16x9.mp4   # masters per aspect
captions_ar.srt captions_en.srt  # both languages
thumb_1080.jpg
COSTS.csv                  # model, dur_s, resolution, usd per job
```

## 7. Agent checklist

```
- [ ] Brief captured; aspect ratio + fps locked BEFORE first generation
- [ ] STORYBOARD.json exists with seed per shot (reproducible)
- [ ] Hook lands in first 1–2s; one idea per shot
- [ ] No legible text baked into AI frames (Remotion overlay instead)
- [ ] Captions authored for muted autoplay (both languages if bilingual)
- [ ] 2 fallback models configured; queue + retries wired
- [ ] Cost log written per job; projected total ≤ ceiling
- [ ] Rights cleared: likeness consent, music license, AI-content label if required
- [ ] QA gate passed (ai-video-qa-evaluation) before publish
```

## 8. Anti-patterns

- **One 30–60s mega-prompt** → incoherent motion, morphing, wasted spend. Decompose into shots.
- **Generate-then-design** — choosing aspect ratio after rendering forces a full reburn.
- **No seed capture** — every client note becomes a fresh gamble.
- **Single-vendor lock-in** — no fallback = your launch depends on one provider's uptime.
- **Burning text/price/logo into generative frames** — un-editable, off-brand, warps.
- **Skipping captions** — ~85% of social plays are muted; no captions = no message.

## 9. References

- fal.ai video models: https://fal.ai/models?categories=text-to-video
- Veo 3.1 prompting guide (Google Cloud): https://cloud.google.com/blog/products/ai-machine-learning/ultimate-prompting-guide-for-veo-3-1
- Remotion docs: https://www.remotion.dev/docs/

## Related

All `video-ai-master` skills. Brand tokens → `color-design-master`; ad copy → `content-seo-master`;
prompt engineering → `ai-mcp-master`.
