---
name: ai-video-qa-evaluation
description: >-
  Automated QA gate for AI/Remotion video before publish: ffprobe spec validation, black/freeze/silence
  detection, two-pass loudness check, A/V sync + duration/aspect/safe-zone checks, vision-LLM artifact &
  brand-safety review, and golden/regression tests in CI. Use as the release gate after post-production.
---

# AI Video QA & Evaluation

**Mandate:** AI video fails in ways humans miss at 2× scrub — warped hands for 6 frames, a frozen last second,
−9 LUFS loudness, a caption under the TikTok button, a 16:9 master mislabeled 9:16. **Gate every deliverable
with automated checks** so bad renders never reach a client or feed. QA is a CI step, not a vibe at the end.

## When to use / NOT use

- **Use** as the release gate after `video-ffmpeg-post-production`, and per-shot to reject bad generations early.
- **NOT** as a substitute for the cinematic-prompt/storyboard discipline upstream — QA catches defects, it doesn't author quality.

## Check matrix (what to assert, how)

| Class | Check | Tool | Fail if |
|-------|-------|------|---------|
| Container | codec/profile/pix_fmt/faststart | `ffprobe` | not H.264 High / not yuv420p / no `+faststart` |
| Geometry | width/height/aspect/fps | `ffprobe` | ≠ STORYBOARD `master_aspect`/`fps`/`resolution` |
| Duration | total + per-shot length | `ffprobe` | drift > 1 frame from plan |
| Dead frames | black / frozen start-end | `blackdetect`,`freezedetect` | black > 0.2 s or freeze > 0.5 s |
| Audio presence | silence / channels / rate | `silencedetect`,`ffprobe` | unexpected silence or wrong sample rate |
| Loudness | integrated LUFS / true peak | `ebur128` | I outside −14 ±1 LUFS or TP > −1 dBTP |
| A/V sync | audio start offset | `ffprobe` packets | |offset| > 1 frame |
| Captions | present + inside safe zone | parser + geometry | missing, or text in blocked UI band |
| Visual | warped faces/hands, morphing, watermark | vision LLM on sampled frames | model flags artifact/brand-unsafe |
| Brand | logo/color/legal present on end card | vision LLM / pixel check | required element absent |

## 1. Spec validation (machine-readable)

```bash
ffprobe -v error -show_entries stream=codec_name,profile,width,height,r_frame_rate,pix_fmt,sample_rate,channels \
  -show_entries format=duration,format_name -of json final_9x16.mp4 > probe.json
```

```python
import json, subprocess
p = json.loads(subprocess.check_output(["ffprobe","-v","error","-print_format","json",
     "-show_streams","-show_format","final_9x16.mp4"]))
v = next(s for s in p["streams"] if s["codec_type"]=="video")
assert v["codec_name"]=="h264" and v["pix_fmt"]=="yuv420p", "codec/pixfmt"
assert (int(v["width"]),int(v["height"]))==(1080,1920), "geometry != 9:16 master"
assert eval(v["r_frame_rate"])==30, "fps != 30"
assert abs(float(p["format"]["duration"]) - 30.0) < 0.05, "duration drift"
```

## 2. Dead-frame, freeze, silence detection

```bash
ffmpeg -i final.mp4 -vf "blackdetect=d=0.2:pix_th=0.10" -an -f null - 2>&1 | grep blackdetect
ffmpeg -i final.mp4 -vf "freezedetect=n=-60dB:d=0.5" -an -f null - 2>&1 | grep freeze
ffmpeg -i final.mp4 -af "silencedetect=n=-50dB:d=0.8" -vn -f null - 2>&1 | grep silence
```

Frozen final second and silent VO are the two most common AI-video ship defects — assert against both.

## 3. Loudness gate (measure, then assert)

```bash
ffmpeg -i final.mp4 -af loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json -f null - 2>&1 | tail -20
# parse measured_I / measured_TP → fail the build if outside tolerance
```

## 4. Vision-LLM frame review (artifacts + brand safety)

```python
# Sample frames (1 fps), ask a multimodal model to grade each — cheap insurance vs warped hands/text/watermarks.
import subprocess, base64, json
subprocess.run(["ffmpeg","-i","final.mp4","-vf","fps=1","-q:v","2","frames/%03d.jpg","-y"], check=True)

RUBRIC = ("Return JSON {artifact:bool, issues:[], brand_safe:bool, readable_text_ok:bool}. "
          "Flag: warped/extra fingers, melted faces, morphing, watermark/logo bleed, gibberish on-screen text, "
          "NSFW/unsafe content. readable_text_ok=false if any garbled text is visible in-frame.")
def grade(path):
    img = base64.b64encode(open(path,"rb").read()).decode()
    # call your multimodal model (e.g. Gemini / GPT-4-class) with RUBRIC + img; parse JSON
    return call_vision_model(RUBRIC, img)

reports = [grade(f) for f in sorted(__import__("glob").glob("frames/*.jpg"))]
assert not any(r["artifact"] for r in reports), "visual artifact detected"
assert all(r["brand_safe"] for r in reports), "brand-safety fail"
```

Sample at 1–2 fps (not every frame) to control cost; escalate flagged segments to a human.

## 5. Caption safe-zone check

```python
# captions must be non-empty AND positioned within the platform safe band (see video-social-export-specs)
# For burned-in subs, assert the caption region sits within Y 220–1440 on a 1080×1920 canvas.
assert srt_has_cues("captions_en.srt"), "no captions"
assert caption_marginV >= 120 and caption_top_y >= 220, "caption under UI safe zone"
```

## 6. Golden / regression tests (Remotion + deterministic clips)

```bash
# Remotion is deterministic → snapshot a known frame and diff on every change
npx remotion still src/index.ts Promo out/frame90.png --frame=90
# compare to golden/ with a perceptual diff (pixelmatch/odiff); fail CI on > threshold delta
```

Pin the Remotion version (renders can change across patches) so goldens stay valid.

## CI gate

```yaml
# .github/workflows/video-qa.yml
- run: python qa/spec_check.py final_9x16.mp4
- run: bash qa/deadframe_loudness.sh final_9x16.mp4
- run: python qa/vision_review.py final_9x16.mp4      # needs model API key (secret)
- run: python qa/caption_check.py captions_en.srt
# any non-zero exit blocks the publish/upload step
```

## Observability (track defect rates, not just pass/fail)

```ts
type QaReport = { asset:string; model:string; checks:Record<string,"pass"|"fail">;
  lufs:number; artifacts:number; cost_usd:number; reroll_count:number; ts:string };
await db.qa.insert(report);   // dashboards: reroll rate by model, top failing check, $ per PASSED asset
```

The signal that pays for itself: **which model/prompt classes reroll most** → route away from them (feeds `ai-video-models-selection`).

## Performance / cost

- ffprobe/ffmpeg checks are ~free and fast — run on every shot.
- Vision-LLM review is the cost driver: sample frames (1 fps), short rubric, batch, cache by frame hash; only escalate flagged ranges to humans.

## Edge cases / gotchas

- **VFR clips** report misleading `r_frame_rate` — normalize to CFR first (post skill), then check.
- **`blackdetect` false-positives** on intentional black intros — exclude the first/last N frames if by-design.
- **Loudness measured pre-mux** ≠ delivered — always probe the **final muxed** file.
- **Vision model nondeterminism** — fix a low temperature + strict JSON schema; treat as a flag, not absolute truth.
- **Goldens drift** after a deliberate creative change — update goldens in the same PR, never silence the check.

## Agent checklist

```
- [ ] ffprobe asserts codec/pixfmt/geometry/fps/duration vs STORYBOARD
- [ ] black/freeze/silence detection clean (esp. final second + VO)
- [ ] loudness measured on FINAL muxed file, −14 ±1 LUFS / TP ≤ −1 dBTP
- [ ] captions present + inside platform safe zone (both languages if bilingual)
- [ ] vision review on sampled frames: no artifacts, brand-safe, no garbled text
- [ ] Remotion goldens diffed; version pinned
- [ ] QA report logged (reroll rate, failing check, $ per passed asset)
- [ ] CI gate blocks publish on any failure
```

## Anti-patterns

- "Looks fine in the Studio preview" → preview ≠ render; probe the delivered file.
- Checking the master but shipping a different re-encode → QA the exact published artifact.
- Vision-reviewing every frame (cost blowout) instead of sampling + escalating.
- Disabling a failing golden to make CI green instead of fixing or updating it.

## References

- ffmpeg detect filters: https://ffmpeg.org/ffmpeg-filters.html#blackdetect (also `freezedetect`, `silencedetect`, `ebur128`)
- Remotion stills (golden frames): https://www.remotion.dev/docs/renderer/render-still

## Related

`video-ffmpeg-post-production`, `video-social-export-specs`, `ai-video-models-selection`, `video-ai-production-workflow`
