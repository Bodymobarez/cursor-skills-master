# Prompting Patterns: iOS Voice

## TTS patterns

1. **Chunk by intent**: one utterance per semantic unit.
2. **Prosody by role**: slower rate for instructions, normal for confirmations.
3. **Pronunciation-safe terms**: IPA/SSML for difficult words.
4. **Locale lock**: voice language = content language.
5. **Accessibility**: align with assistive-technology speech settings.
6. **Voice fallback**: preferred identifier → locale match → system default.
7. **Pause shaping**: pre/post delays to separate list items and steps.
8. **Progress-synced UI**: drive highlights from delegate callbacks.
9. **Interruptibility**: pause/continue/stop boundaries for correction.
10. **Route-aware**: consider telephony and audio-session options.

## STT patterns

1. **Mode declaration**: tell user command vs dictation upfront.
2. **Constrained grammar**: small explicit command set for control flows.
3. **Context bias**: preload entities in `contextualStrings`.
4. **Final-result gating**: irreversible actions only on final transcripts.
5. **On-device preference**: when privacy/latency matter.
6. **Session closure**: `endAudio()` to force finalization.
7. **Domain adaptation**: `SFCustomLanguageModelData` with weighted phrases.
8. **Pronunciation injection**: X-SAMPA for specialized vocabulary.
9. **Availability UX**: reflect recognizer availability in controls.
10. **Volatile/final separation**: render interim text distinctly until final.

## Example user-facing prompts

- **TTS setup**: "I will read this in short steps. Say 'pause' anytime."
- **STT command**: "Say one command: Start, Stop, Retry."
- **STT dictation**: "Speak naturally. I'll show live text and confirm final output."
- **STT command (domain)**: "Say one command: Start timer, Stop timer, or Repeat last."
- **STT domain boost**: "You can use project terms like Winawer, Tartakower, and counter gambit."

## App Shortcuts / Siri

- App Shortcuts allow preconfigured spoken phrases for voice invocation.
- Parameterized phrases reduce Siri clarification turns.
- Prefer concise, unique commands tied to a single action.
