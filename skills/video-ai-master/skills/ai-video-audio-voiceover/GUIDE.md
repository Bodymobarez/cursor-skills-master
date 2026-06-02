---
name: ai-video-audio-voiceover
description: >-
  Audio layer for AI video at staff depth: ElevenLabs TTS voiceover (eleven_v3 / multilingual_v2 / flash_v2_5),
  music (Eleven Music music_v1), SFX, dubbing/localization, and word-level timestamps (scribe_v2 / forced
  alignment) feeding captions. Use to score, narrate, dub, and sound-design generated video (esp. silent models).
---

# AI Video Audio & Voiceover

**Mandate:** half of "video quality" is **audio**. Most generative models (Kling, Luma, Pika, Wan) ship **silent**,
and even Veo/Sora audio is uncontrollable for brand VO. Own the audio layer explicitly: scripted VO, licensed
music bed, SFX, and word-level timestamps that drive captions. Generate timestamps **from the real VO**, not guesses.

## When to use / NOT use

- **Use** for narration, music, SFX, dubbing, and caption timing on any AI/Remotion video — especially silent-model shots.
- **NOT** for lip-synced on-screen presenters (that's `ai-avatar-presenter-video`) or native ambient audio you intentionally keep from Veo/Sora.

## Audio stack decision matrix

| Need | Tool / model | Endpoint | Bill |
|------|--------------|----------|------|
| Brand voiceover (expressive, multi-speaker, tags) | **ElevenLabs `eleven_v3`** (70+ langs, `[laughs]` tags, 5k char) | `POST /v1/text-to-speech/{voice_id}` | per char |
| Long-form / highest fidelity narration | `eleven_multilingual_v2` (10k char) | same | per char |
| Low-latency / realtime / long scripts | `eleven_flash_v2_5` (32 langs, 40k char) | same | per char |
| Music bed | **Eleven Music `music_v1`** (text → studio music) | Music API | per generation |
| SFX (whooshes, impacts, ambience) | `eleven_text_to_sound_v2` | Sound Effects API | per generation |
| Dub existing video to new languages | **Dubbing API** | `POST /v1/dubbing` | per source min |
| Word-level caption timing | `scribe_v2` (STT, diarization) / Forced Alignment | STT / alignment API | per audio min |

## TTS — ElevenLabs (verified)

```bash
curl -X POST "https://api.elevenlabs.io/v1/text-to-speech/21m00Tcm4TlvDq8ikWAM?output_format=mp3_44100_128" \
  -H "xi-api-key: $ELEVENLABS_API_KEY" -H "Content-Type: application/json" \
  -d '{
    "text": "Renew your license in three simple steps.",
    "model_id": "eleven_v3",
    "voice_settings": { "stability": 0.5, "similarity_boost": 0.75, "style": 0.0, "use_speaker_boost": true }
  }' --output vo_en.mp3
```

```ts
// Node SDK: npm i @elevenlabs/elevenlabs-js
import { ElevenLabsClient } from "@elevenlabs/elevenlabs-js";
const el = new ElevenLabsClient({ apiKey: process.env.ELEVENLABS_API_KEY! });

const audio = await el.textToSpeech.convert("21m00Tcm4TlvDq8ikWAM", {
  text: "ابدأ اليوم ووفّر وقتك.",
  modelId: "eleven_multilingual_v2",          // Arabic / multilingual
  outputFormat: "mp3_44100_128",
  voiceSettings: { stability: 0.55, similarityBoost: 0.8 },
});
// stream `audio` to vo_ar.mp3
```

- `output_format` is `codec_sampleRate_bitrate` (e.g. `mp3_44100_128`, `pcm_48000` for editing).
- `eleven_v3` supports inline **audio tags** (`[whispers]`, `[laughs]`, `[sighs]`) and multi-speaker dialogue.
- Tune `stability` (lower = more expressive/variable, higher = consistent reads) per brand tone.

## Music & SFX

```ts
// Eleven Music — generate a licensed bed from a prompt (model music_v1)
const music = await el.music.compose({ prompt: "upbeat optimistic corporate, light percussion, 30s, no vocals", musicLengthMs: 30000 });
// SFX
const sfx = await el.textToSoundEffects.convert({ text: "soft UI whoosh transition", durationSeconds: 1.2 });
```

Generate the bed at the **edit length** and let ffmpeg sidechain-duck it under VO (see post skill). Keep music vocal-free under speech.

## Dubbing (localize an existing cut)

```bash
curl -X POST "https://api.elevenlabs.io/v1/dubbing" \
  -H "xi-api-key: $ELEVENLABS_API_KEY" -F file=@final_en.mp4 -F target_lang=ar -F num_speakers=1
# → dubbing_id; poll status, then download the dubbed render
```

Dubbing translates + revoices while preserving timing — faster than re-cutting per locale. Always **human-review pronunciation** of brand names/numbers before publish.

## Word-level timestamps → captions (the integration that matters)

Generate timing from the **actual VO audio** so captions land on the word:

```python
# Option A: transcribe the VO → token timestamps (feeds @remotion/captions or SRT)
# ElevenLabs scribe_v2 (diarization) OR Whisper.cpp tokenLevelTimestamps (see remotion skill)
# Option B: Forced Alignment — you already have the script, align it to the audio for exact word times
```

Then drive `createTikTokStyleCaptions()` (Remotion) or emit SRT for ffmpeg burn-in. Never hand-time captions for scripted VO — align them.

## Mixing handoff (to ffmpeg)

```
1. Render VO (TTS) at 48 kHz.
2. Generate/clear music bed; SFX as needed.
3. ffmpeg: sidechain-duck music under VO → two-pass loudnorm to −14 LUFS / −1.5 dBTP.
4. Mux onto the picture; verify with ffprobe (channels, sample_rate). (video-ffmpeg-post-production)
```

## Security / rights / policy

- API key server-side only (`ELEVENLABS_API_KEY`); never in client bundles.
- **Voice cloning needs consent** — only clone a voice you have written rights to; respect ElevenLabs voice policy.
- Music/SFX: confirm the provider's commercial-use license covers your distribution + platform.
- Disclose AI-generated voice where the market/platform requires it.

## Performance / cost

- TTS billed **per character** — cache by `hash(text+voice+model)`; don't re-synthesize unchanged lines on every render.
- Use `eleven_flash_v2_5` for drafts/iteration, promote final reads to `eleven_v3`/`multilingual_v2`.
- Music/SFX billed per generation; dubbing per source minute — batch and cache.

## Edge cases / gotchas

- **`eleven_v3` 5k-char limit** → chunk long scripts; pass `previous_text`/`next_text` for seamless continuity across chunks.
- **Numbers/acronyms/prices** mis-read → use pronunciation dictionaries or spell phonetically in the script.
- **Arabic with an English voice** → wrong phonemes; pick an Arabic/multilingual voice and verify diacritics.
- **Caption timing from the script instead of the audio** → drift; always time off the rendered VO.
- **Music louder than VO** → fix with sidechain ducking, not a static volume guess.

## Agent checklist

```
- [ ] VO model matches language + tone (eleven_v3 / multilingual_v2 / flash draft)
- [ ] output_format 48k for editing; cached by text+voice+model hash
- [ ] Music bed vocal-free, generated at edit length, ducked under VO
- [ ] Captions timed from rendered VO (scribe/forced-alignment), not the script
- [ ] Loudness normalized −14 LUFS / −1.5 dBTP in the mix
- [ ] Voice-clone consent + commercial license + AI disclosure handled
```

## Anti-patterns

- Shipping silent Kling/Luma B-roll with no audio pass.
- Static `volume=0.25` music instead of VO-triggered ducking.
- Hand-timed captions for scripted narration (use alignment).
- Cloning a real voice without consent, or assuming music is license-free.

## References

- ElevenLabs TTS: https://elevenlabs.io/docs/api-reference/text-to-speech/convert · models: https://elevenlabs.io/docs/overview/models
- Dubbing: https://elevenlabs.io/docs/api-reference/dubbing · Music: https://elevenlabs.io/docs/overview/models

## Related

`video-ffmpeg-post-production`, `remotion-programmatic-video`, `ai-avatar-presenter-video`, `video-social-export-specs`
