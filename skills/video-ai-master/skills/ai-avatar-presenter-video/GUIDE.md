---
name: ai-avatar-presenter-video
description: >-
  Script → talking-head presenter at production depth: HeyGen v3 (/v3/videos, Avatar IV/V) + v2 legacy,
  Synthesia (/v2/videos, /fromTemplate, green-screen), real payloads, polling/webhooks, localization,
  SSML/pronunciation, likeness consent + AI-labeling, and chroma-key compositing. Use for presenter video.
---

# AI Avatar & Presenter Video

**Mandate:** avatars are for **script-driven presenters** (training, explainers, multilingual spokespeople) —
not cinematic B-roll. Treat them like a publishing pipeline: **approved script → generate → poll → human QA →
publish**, with consent + AI-labeling as hard gates. The expensive mistakes here are legal (likeness), not visual.

## When to use / NOT use

| Use avatars | Don't |
|-------------|-------|
| Training / onboarding / SOP videos | cinematic ad B-roll → Veo/Kling |
| Same face across 30 languages | crowd/lifestyle scenes → generative |
| UGC-style spokesperson at volume | a real exec's likeness without written consent |
| Internal CEO / policy message | "live"/news framing implying it's real footage |

## Provider decision matrix

| Provider | Endpoint (2026) | Strengths | Notes |
|----------|-----------------|-----------|-------|
| **HeyGen v3** | `POST https://api.heygen.com/v3/videos` | newest engines (Avatar IV/V), talking-photo, webm alpha | active platform; all new features here |
| **HeyGen v2** | `POST https://api.heygen.com/v2/video/generate` | stable, widely integrated | **legacy — supported through Oct 31 2026**; migrate to v3 |
| **Synthesia** | `POST https://api.synthesia.io/v2/videos` (+ `/fromTemplate`) | enterprise templates, 140+ langs, green-screen | API is **Enterprise-plan only** |

## HeyGen v3 (active) — generate

```bash
curl -X POST https://api.heygen.com/v3/videos \
  -H "X-Api-Key: $HEYGEN_API_KEY" -H "Content-Type: application/json" \
  -d '{
    "avatar_id": "Daisy-inskirt-20220818",
    "script": "Welcome to our digital service. Today I will show you how to renew your license in three steps.",
    "voice_id": "1bd001e7e50f421d891986aad5158bc8",
    "aspect_ratio": "9:16",
    "background": { "type": "color", "value": "#0F172A" },
    "callback_url": "https://api.example.com/webhooks/heygen",
    "callback_id": "lesson-01"
  }'
```

- Exactly **one visual source**: `avatar_id` | `image_url` | talking-photo. Omit `voice_id` with `avatar_id` to use the avatar's default voice.
- `output_format:"webm"` returns an **alpha channel** (transparent bg) for compositing — rejects `background`.
- Set `engine` to pick Avatar IV (default) vs Avatar V; check the avatar's `supported_api_engines`.
- Avatar III generation requires the **legacy v1/v2** API.

## HeyGen v2 (legacy until 2026-10-31)

```jsonc
{ "video_inputs": [{
    "character": { "type": "avatar", "avatar_id": "josh_lite3_20230714", "avatar_style": "normal" },
    "voice":     { "type": "text", "input_text": "مرحباً بكم في خدمتنا الرقمية.", "voice_id": "<ar-voice>", "speed": 1.0, "pitch": 0 },
    "background":{ "type": "color", "value": "#0F172A" }
  }],
  "dimension": { "width": 1080, "height": 1920 } }
```

`voice.type` ∈ `text`|`audio`|`silence`; `character.type` ∈ `avatar`|`talking_photo`. Don't build new work on v2 — wire v3 and keep v2 only for existing pipelines.

## Synthesia — create video (+ green-screen for chroma key)

```bash
curl -X POST https://api.synthesia.io/v2/videos \
  -H "Authorization: $SYNTHESIA_API_KEY" -H "Content-Type: application/json" \
  -d '{
    "title": "License Renewal — AR",
    "visibility": "private", "aspectRatio": "9:16", "test": true,
    "input": [{
      "scriptText": "مرحباً، سأوضح لك كيفية تجديد رخصتك في ثلاث خطوات.",
      "avatar": "anna_costume1_cameraA",
      "avatarSettings": { "voice": "ar-AE-male-1", "horizontalAlign": "center", "scale": 1, "style": "rectangular" },
      "background": "green_screen"
    }]
  }'
```

- **Auth is the raw key** in `Authorization` (no `Bearer` per Synthesia docs).
- `background: "green_screen"` → composite over your own scene with ffmpeg `chromakey` (see post skill); or use solid/image presets.
- `test: true` = **free, watermarked** — always iterate in test mode, flip to `false` only for the final render.
- `scriptAudio` + `scriptLanguage` lets you supply your own VO instead of `scriptText`.
- Template route for personalization at scale: `POST /v2/videos/fromTemplate` with `templateId` + `input` placeholders.

## Poll / webhook

```python
import os, time, requests
H = {"X-Api-Key": os.environ["HEYGEN_API_KEY"]}
def wait(video_id):
    while True:
        s = requests.get(f"https://api.heygen.com/v1/video_status.get?video_id={video_id}", headers=H).json()
        st = s["data"]["status"]
        if st == "completed": return s["data"]["video_url"]
        if st == "failed":    raise RuntimeError(s["data"].get("error"))
        time.sleep(10)
```

Prefer `callback_url` (HeyGen) / webhooks over tight polling for batch. Synthesia: `GET /v2/videos/{id}` until `status:"complete"`. Both can take minutes per video — never block a user request on it.

## Localization (same face, many languages)

```
1. Author + LEGAL-review the source script (one language).
2. Translate per locale; keep sentences short (lip-sync drifts on long clauses).
3. Pick a locale-correct voice_id; test pronunciation of brand names + numbers.
4. Generate per locale; tag output { locale, script_hash } for traceability.
```

- **Arabic / RTL:** verify diacritics and brand-name pronunciation; use an Arabic voice, not an English voice reading transliteration. Burn RTL captions in Remotion/ffmpeg if required.
- Use SSML / pronunciation dictionaries (where supported) for acronyms, prices, and proper nouns.

## Combine with generative B-roll

Avatar intro (HeyGen, alpha/webm) → composite over a Veo street scene → cut to product B-roll (Kling) → Remotion CTA end card. Keep the avatar on its own track so you can re-dub per locale without re-rendering B-roll.

## Compliance / security (hard gates)

```
- [ ] Written consent for any real person's likeness/voice (scope, duration, territory)
- [ ] AI-generated disclosure where the market/platform requires it
- [ ] No deceptive "live"/news framing; no political impersonation
- [ ] Human review of lip-sync + pronunciation BEFORE publish
- [ ] API key server-side; callback endpoints signed/verified; outputs stored with access control
```

## Edge cases / gotchas

- **Long monologues** → lip-sync drift + pacing issues. Break into shorter takes/sentences.
- **webm alpha + background set** → request rejected. Choose one (transparent OR background).
- **`test:true` left on** → watermark ships to production. Gate the flag in code.
- **Locale/voice mismatch** (English voice on Arabic text) → mispronunciation. Match voice to script language.
- **Provider minutes/concurrency limits** → queue and backoff for batch localization runs.

## Performance / cost

- Billed per video / per minute of output (plan-dependent). Batch overnight; cache by `script_hash` so re-runs of unchanged scripts don't re-bill.
- Generate once at the **highest aspect** you need and derive crops, or render per-aspect if framing matters.

## Agent checklist

```
- [ ] Script approved + legally reviewed before any generation
- [ ] v3 used for new work (v2 only for existing; migrate before 2026-10-31)
- [ ] Voice matches script language; pronunciation tested
- [ ] Consent + AI-label + human QA gates satisfied
- [ ] Callback/poll handled async; outputs persisted to own storage
- [ ] test/watermark flag OFF only for final render
```

## Anti-patterns

- Using an avatar for cinematic B-roll (uncanny, stiff) instead of generative video.
- Cloning a real exec's likeness without written consent.
- Shipping watermarked `test` renders, or English-voiced Arabic scripts.
- Blocking a web request on a multi-minute avatar render instead of webhook/poll.

## References

- HeyGen v3: https://developers.heygen.com/reference/create-video · v2 (legacy): https://docs.heygen.com/reference/create-an-avatar-video-v2
- Synthesia API: https://docs.synthesia.io/reference/create-video

## Related

`ai-video-audio-voiceover`, `video-ffmpeg-post-production`, `video-social-export-specs`, `video-ai-production-workflow`
