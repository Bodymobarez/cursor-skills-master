# API Reference and Apple Docs

## STT (Speech framework)

| Type | Notes |
|------|-------|
| `SFSpeechRecognizer` | Locale-bound; check availability before use |
| `SFSpeechRecognitionRequest` | `shouldReportPartialResults`, `requiresOnDeviceRecognition`, `contextualStrings`, `taskHint`, `addsPunctuation` |
| `SFSpeechAudioBufferRecognitionRequest` | Live mic; requires `append(buffer)` and explicit `endAudio()` |
| `SFCustomLanguageModelData` | Weighted phrases, templates, X-SAMPA for domain vocabulary |

## TTS (AVFAudio)

| Type | Notes |
|------|-------|
| `AVSpeechSynthesizer` | Queue model; app must retain until done; `pauseSpeaking(at:)`, `continueSpeaking()`, `stopSpeaking(at:)` |
| `AVSpeechUtterance` | `rate`, `pitchMultiplier`, `volume`, `preUtteranceDelay`, `postUtteranceDelay`; SSML/IPA for pronunciation |
| `AVSpeechSynthesisVoice` | Select by identifier or language; fallback chain: identifier → locale → default |
| `AVSpeechSynthesizerDelegate` | `willSpeakRangeOfSpeechString`, `didFinish` for UI sync |

**Accessibility**: `prefersAssistiveTechnologySettings = true` aligns with assistive tech speech. For telephony: `mixToTelephonyUplink`; for complex audio: `usesApplicationAudioSession = false`.

## Apple documentation

**Speech (STT)**
- [Speech framework](https://developer.apple.com/documentation/speech)
- [Asking permission](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition)
- [Recognizing speech in live audio](https://developer.apple.com/documentation/speech/recognizing-speech-in-live-audio)
- [SFSpeechRecognizer](https://developer.apple.com/documentation/speech/sfspeechrecognizer)
- [SFSpeechRecognitionRequest](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest)
- [SFSpeechAudioBufferRecognitionRequest](https://developer.apple.com/documentation/speech/sfspeechaudiobufferrecognitionrequest)
- [SFCustomLanguageModelData](https://developer.apple.com/documentation/speech/sfcustomlanguagemodeldata)

**AVSpeech (TTS)**
- [AVSpeechSynthesizer](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer)
- [AVSpeechUtterance](https://developer.apple.com/documentation/avfaudio/avspeechutterance)
- [AVSpeechSynthesisVoice](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoice)
- [AVSpeechSynthesizerDelegate](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizerdelegate)

**Modern APIs**
- [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer) — long-form, distant-audio (newer)
- [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber) — conversation-style transcription

**Voice invocation**
- [App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts)
