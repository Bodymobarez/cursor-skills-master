---
name: ai-video-cinematic-prompts
description: >-
  Write cinematic AI video prompts that hold up in production: Google's verified 5-part Veo 3.1 formula,
  film-grammar vocabulary (shot/lens/move/light), native dialogue+SFX syntax, negative prompts, seed
  locking, and Arabic/RTL scene direction. Use to author every per-shot prompt before generating.
---

# AI Video Cinematic Prompts

**Mandate:** one shot = one prompt = one action. Prompts are **camera direction, not wishes** — name the
shot size, lens, move, and light in film language. Vague prompts ("nice video of a city") waste metered
seconds and produce morphing slop. Lock the seed so iteration is editing, not gambling.

## When to use / NOT use

- **Use** to turn a storyboard row into a precise, reproducible prompt for Veo/Kling/Sora/Runway.
- **NOT** to cram dialogue + on-screen text + 3 actions into one clip. Split shots; overlay text in Remotion.

## The formula (Google's official Veo 3.1 structure)

```
[Cinematography] + [Subject] + [Action] + [Context] + [Style & Ambiance]
```

Put **cinematography first** — the model weights leading tokens heavily, and camera/shot is where most
prompts fail. Equivalent expanded template (VEED/Google):

```
[Shot composition], [Subject + physical detail], [single Action],
[Environment + time], [Camera movement], [Lens/DOF], [Style + mood + lighting], [audio]
```

## Film-grammar vocabulary (be specific or be generic)

| Axis | Use these, not "nice/cool" |
|------|----------------------------|
| Shot size | extreme wide · wide establishing · medium · medium close-up · close-up · macro · OTS · POV · top-down |
| Camera move | static · slow dolly in/out · pan L/R · tracking · orbit/arc · crane up · handheld subtle · push-in *(avoid whip pan — risky)* |
| Lens / DOF | 24mm wide · 35mm · 50mm natural · 85mm portrait · shallow DOF · deep focus · rack focus |
| Lighting | golden hour · soft window light · neon practicals · high-key studio · rim/back light · overcast diffuse · chiaroscuro |
| Grade / look | filmic · muted pastel · teal-orange · warm 3200K · cool 5600K · 35mm grain · clean digital |

## Production example (EN, Veo 3.1)

```text
Medium close-up, rule-of-thirds, a barista (early 30s, apron, tied-back hair) pouring latte art
into a ceramic cup, cozy specialty cafe at morning, warm side light from a large window,
slow push-in, 50mm shallow depth of field, filmic with subtle 35mm grain, calm inviting mood.
Audio: ambient espresso machine hiss and low cafe murmur, no music.
```

## Native dialogue + audio (Veo 3.1 / Sora 2 only)

```text
Two-person street interview, Dubai Marina, late afternoon sun, medium shot, 35mm.
Dialogue:
Host: "what changed your workflow?"
Guest: "the new digital service saved me hours every week."
Audio: natural ambient marina tone, subtle wind, no background music.
```

- Use **lowercase** for spoken English (per Kling/Veo convention); keep proper nouns capitalized.
- Keep lines short — long monologues drift lip-sync. For >1 line of dialogue, prefer Veo 3.1 or Sora 2.
- Silent models (Kling/Luma/Pika/Wan): describe SFX only as *intent*; add real audio in `ai-video-audio-voiceover`.

## Negative prompt (append where supported: Veo, Kling, Pika, Wan)

```text
blurry, distorted face, extra fingers, deformed limbs, morphing objects, flicker, jitter,
watermark, on-screen text, logo burn-in, subtitles, oversaturated, plastic skin, warped hands
```

Kling's default is `"blur, distort, and low quality"` — extend it, don't blank it.

## Reproducibility

```jsonc
{ "shot": "01_hook", "model": "fal-ai/veo3.1", "seed": 4412,
  "negative_prompt": "…", "notes": "client approved v3 — DO NOT reroll seed" }
```

Lock `seed` before review. A client note then changes 5 words, not the entire clip. Store prompt+seed per shot (`PROMPTS/01.txt`).

## Arabic / RTL scene direction

- Author the **machine prompt in English** (models are English-trained) — but specify culturally accurate
  wardrobe, setting, and on-set signage as *"no readable text on screen"* (add Arabic text in Remotion, RTL-correct).
- For Arabic VO, write the script separately for `ai-video-audio-voiceover` (ElevenLabs `eleven_v3`, 70+ langs).
- Government/enterprise UAE look: clean architectural light, trustworthy mood, restrained motion. Example:

```text
Wide establishing, modern Abu Dhabi government service hall, a citizen walking toward a digital kiosk,
bright clean daylight, slow tracking shot, 35mm, professional trustworthy mood, quiet ambient hall tone.
No readable text on screens.
```

## First-last-frame & reference prompts

When using `veo3.1/first-last-frame-to-video` or Kling `tail_image_url`, the prompt describes the **transition
and audio between the two frames**, not the frames themselves:

```text
The camera performs a smooth 180° arc from the front-facing view to a POV behind the subject on stage.
Audio: the singer sings the opening line softly. Seamless, continuous motion.
```

## Edge cases / gotchas

- **Three actions in one prompt** → the model averages them into mush. One verb per clip.
- **Requesting on-screen text** → warped glyphs every time. Forbid it in the negative prompt; overlay in post.
- **Over-long prompts** dilute the leading camera tokens — front-load shot + move, trim adjectives.
- **Wardrobe/lighting drift across shots** breaks continuity — copy the exact character-bible sentence every shot (`ai-image-to-video-consistency`).
- **Profanity/likeness/brand names** can trip content policy → `auto_fix` rewrites silently (pin seed to detect drift).

## Agent checklist

```
- [ ] Cinematography token is FIRST
- [ ] Exactly one action/verb
- [ ] Lens + camera move + lighting named explicitly
- [ ] No on-screen text requested; it's in the negative prompt
- [ ] Dialogue only on audio-capable models, lowercase, short lines
- [ ] Seed locked + prompt saved per shot
- [ ] Same character-bible sentence reused across recurring-subject shots
```

## Anti-patterns

- "cinematic, 4k, beautiful, masterpiece" keyword soup — adds nothing, models aren't tag-soup image gen.
- Describing edits ("then it cuts to…") inside one clip — cuts happen in assembly, not in a prompt.
- Writing the prompt in Arabic for an English-trained model and hoping — author EN, localize audio/text separately.

## References

- Veo 3.1 prompting guide (Google Cloud): https://cloud.google.com/blog/products/ai-machine-learning/ultimate-prompting-guide-for-veo-3-1
- Veo 3.1 on fal (schema): https://fal.ai/models/fal-ai/veo3.1

## Related

`ai-video-storyboard-multishot`, `ai-image-to-video-consistency`, `ai-video-audio-voiceover`, `ai-video-models-selection`
