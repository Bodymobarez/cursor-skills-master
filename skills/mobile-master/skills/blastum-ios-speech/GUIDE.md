---
name: blastum-ios-speech
description: Add on-device speech recognition (STT) and text-to-speech prompting (TTS) to iOS apps. Use when integrating voice input, voice commands, spoken prompts, or speech-driven flows with Apple Speech and AVSpeech APIs.
---
# iOS Speech

Add on-device speech recognition and TTS prompting to iOS apps using Apple's Speech and AVFoundation frameworks.

## When to Use

- Adding mic input for commands or dictation
- Speaking prompts, instructions, or confirmations to users
- Voice-driven flows (ordering, navigation, forms)
- Integrating speech with Foundation Models for free-form interpretation

## Quick Reference

| Topic | Doc |
|-------|-----|
| Full guide | [docs/guide.md](docs/guide.md) |
| Prompting patterns | [docs/prompting-patterns.md](docs/prompting-patterns.md) |
| API reference | [docs/reference.md](docs/reference.md) |

## Essentials

- **Frameworks**: `Speech`, `AVFoundation`
- **STT**: `SFSpeechRecognizer`, `SFSpeechAudioBufferRecognitionRequest`, `AVAudioEngine`
- **TTS**: `AVSpeechSynthesizer`, `AVSpeechUtterance`, `AVSpeechSynthesizerDelegate`
- **Entitlement**: `NSSpeechRecognitionUsageDescription` in Info.plist

## Resources

- [docs/guide.md](docs/guide.md) — Step-by-step integration
- [docs/prompting-patterns.md](docs/prompting-patterns.md) — TTS/STT prompting playbook
- [docs/reference.md](docs/reference.md) — API facts and Apple docs
