---
name: video-production-pro
description: >-
  Condensed AI video production reference (2026). For full step-by-step skills use
  video-ai-master (10 bundled guides). Use for quick model/prompt/ffmpeg reminders.
---

> **Prefer `video-ai-master`** for create/generate/edit video tasks — it bundles
> workflow, APIs, storyboard, avatars, Remotion, and social export as separate guides.

# Professional Video Production

End-to-end video creation: **concept → script → storyboard → shot prompts → generation/render →
edit/post → export per platform**. Two production paths, often combined:

- **Generative (text/image → footage)** for cinematic B-roll & creative scenes.
- **Programmatic (code → video)** for pixel-perfect, data-driven, repeatable videos.

## When to use

- "Make/generate/edit a video", ad, reel, explainer, product demo, B-roll, avatar video,
  or a data-driven/automated video.

---

## Step 1 — Pick the right tool (2026)

There is **no single best model — match the model to the shot.** (Availability changes; verify
before committing a pipeline.)

| Need | Best pick | Notes |
|------|-----------|-------|
| All-around quality, **native audio**, true 4K | **Veo 3.1** (Google) | Best prompt adherence + photorealism |
| **Cheapest premium**, multi-shot, character consistency | **Kling 3.0** | Great cost/quality for volume; native 4K/60fps |
| **Pro editing**, motion brush, timeline/keyframe control | **Runway Gen-4.5** | #1 on Video Arena; for ads/client work |
| **Narrative**, multi-shot coherence, physics | **Sora 2** | ⚠️ API sunsetting late 2026 — plan a fallback |
| Fast indie iteration | **Luma Ray 3** | Friendly UI, longer-sequence consistency |
| Daily social (Reels/TikTok/Shorts) | **Pika 2.2** | Fast, social-optimized |
| **Avatar/presenter** from script | HeyGen / Synthesia / Creatify | Talking-head ads, training, localization |
| **Data-driven / pixel-perfect / automated** | **Remotion** (code) | React → MP4, CI/CD rendering |

**Programmatic API access:** prefer a **multi-model gateway like `fal.ai`** (600+ models incl.
Veo/Kling/Runway/Wan) to avoid lock-in, or the vendor API directly. Pricing is per-second
(~$0.05–0.75/s) or credit-based.

```python
# fal.ai — model-agnostic generation
import fal_client
result = fal_client.subscribe("fal-ai/veo3.1", arguments={
    "prompt": "Cinematic dolly-in on a neon-lit Tokyo street at night, rain reflections, 35mm",
    "resolution": "1080p",
    "generate_audio": True,
})
print(result["video"]["url"])
```

---

## Step 2 — Script & structure

- **Hook (0–3s):** strongest visual/claim first (critical for social).
- **Body:** one idea per shot; keep shots 2–5s for generative models.
- **CTA/close:** clear action or payoff.
- Write a **shot list** before generating anything.

## Step 3 — Cinematic shot prompt formula

Generative models reward **specific, camera-aware** prompts. Structure each shot as:

```
[Shot type] + [Subject + action] + [Setting/time] + [Lighting] + [Camera move] +
[Lens/film look] + [Mood] + [Audio, if supported]
```

Example:
```text
Medium close-up of a barista pouring latte art, cozy morning cafe, warm window light,
slow push-in, 50mm shallow depth of field, film grain, calm and inviting,
ambient cafe sounds.
```

Tips:
- Name **camera moves** (dolly, pan, orbit, crane, handheld) and **lens** (24mm wide, 50mm,
  85mm) — big quality lever.
- Keep **one subject + one action** per shot; complex multi-action prompts drift.
- For **character consistency** across shots, reuse a reference image (Kling/Runway/Veo support
  image-to-video) and identical wardrobe/lighting descriptors.

## Step 4 — Multi-shot storyboarding

For a narrative/ad, generate shots **individually** (most models are strongest at 2–5s clips),
then assemble. Keep a storyboard table:

| # | Shot prompt | Duration | Model | Audio |
|---|-------------|----------|-------|-------|
| 1 | Wide establishing… | 4s | Veo 3.1 | yes |
| 2 | CU reaction… | 3s | Kling 3.0 | — |

---

## Step 5 — Programmatic video with Remotion (data-driven / pixel-perfect)

Use when you need exact text, brand assets, charts, or **batch/automated** videos (e.g. per-user
clips, localized variants) rendered in CI.

```bash
npm create video@latest    # scaffold a Remotion project
# compose React components on a timeline, then render:
npx remotion render src/index.ts MyComp out/video.mp4 --props='{"title":"Hello"}'
```

- Components receive `props` → fully data-driven (loop a dataset to render N videos).
- Combine with generative clips: drop AI B-roll into `<OffthreadVideo>` and overlay
  brand/text/motion-graphics on top.

---

## Step 6 — Post-production (ffmpeg)

```bash
# Concatenate shots
ffmpeg -f concat -safe 0 -i shots.txt -c copy assembled.mp4
# Add music bed (duck under VO if needed)
ffmpeg -i assembled.mp4 -i music.mp3 -filter_complex "[1:a]volume=0.3[a1];[0:a][a1]amix=inputs=2" out.mp4
# Burn captions
ffmpeg -i out.mp4 -vf "subtitles=captions.srt" final.mp4
```

Add: captions (accessibility + silent autoplay), brand intro/outro, color/loudness normalize
(`-af loudnorm`).

## Step 7 — Export per platform

| Platform | Aspect | Notes |
|----------|--------|-------|
| TikTok / Reels / Shorts | 9:16 | Hook in first 1–2s; captions on; ≤ 60–90s |
| YouTube (landscape) | 16:9 | 1080p/4K; thumbnail matters |
| Instagram feed | 1:1 or 4:5 | 4:5 maximizes feed space |
| X / LinkedIn | 16:9 or 1:1 | Captions (muted autoplay) |

---

## Full workflow checklist

```
- [ ] 1. Define goal, platform, length, aspect ratio
- [ ] 2. Write script: hook → body (one idea/shot) → CTA
- [ ] 3. Build shot list / storyboard table
- [ ] 4. Choose model per shot (table above); pick gateway (fal.ai) or vendor API
- [ ] 5. Write camera-aware prompts; reuse refs for character consistency
- [ ] 6. Generate shots (2–5s each) OR render programmatically (Remotion)
- [ ] 7. Assemble + music + captions + brand bumpers (ffmpeg)
- [ ] 8. Normalize loudness/color; export per-platform variants
```

## Anti-patterns

- One giant prompt for a whole multi-shot video → incoherent. Generate shot-by-shot.
- Ignoring audio/captions (most social plays muted).
- Hard-coding a single vendor in an automated pipeline (use a gateway; have a fallback —
  esp. given Sora's API sunset).
- Overlong generative clips → temporal drift; keep shots short and assemble.
- Burning text into AI footage (blurry) → overlay text in Remotion/edit instead.

---
Sources: 2026 AI-video model comparisons (Veo 3.1, Kling 3.0, Runway Gen-4.5, Sora 2, Luma, Pika),
fal.ai multi-model API, and Remotion programmatic rendering.
