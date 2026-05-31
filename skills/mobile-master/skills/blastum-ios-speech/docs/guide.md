# iOS Speech Integration Guide

## Quick Start

1. Add `NSSpeechRecognitionUsageDescription` to Info.plist.
2. Request `SFSpeechRecognizer.requestAuthorization`.
3. Use `SFSpeechAudioBufferRecognitionRequest` + `AVAudioEngine` for live mic.
4. Use `AVSpeechSynthesizer` + `AVSpeechUtterance` for TTS.

## Steps

### 1. Define voice roles

- **Command mode**: small fixed command set; map final transcripts to closed commands.
- **Dictation mode**: free-form text; show live partials, confirm final.
- If using Foundation Models: decide which turns become model prompts vs local commands; which tools (ordering, lookup) are invoked per turn.

### 2. Entitlements and permissions

- Set `NSSpeechRecognitionUsageDescription` in Info.plist.
- Handle authorization flow and error states in UI.

```swift
SFSpeechRecognizer.requestAuthorization { status in
    DispatchQueue.main.async { completion(status) }
}
```

### 3. Wire up speech recognition

- Create `SFSpeechRecognizer` with correct locale.
- Use `SFSpeechAudioBufferRecognitionRequest` + `AVAudioEngine` for live mic.
- Set: `shouldReportPartialResults`, `requiresOnDeviceRecognition`, `taskHint`, `addsPunctuation`.
- Use `contextualStrings` to bias toward app commands/entities.
- Treat partials as volatile UI only; gate irreversible actions on final results.
- Call `endAudio()` to force finalization when user stops.

### 4. Command vs dictation UX

- **Command**: show short list of valid phrases; map final transcript to closed set.
- **Dictation**: show live-updating text for partials; confirm or allow edit on final.

### 5. Text-to-speech prompting

- Retain single `AVSpeechSynthesizer` per screen/controller.
- Voice: preferred identifier → locale match → system default.
- Chunk prompts into multiple utterances (intro, steps, confirmations).
- Shape prosody: `rate`, `pitchMultiplier`, `preUtteranceDelay`, `postUtteranceDelay`.
- Use IPA/SSML for domain-specific pronunciation when needed.

### 6. Sync speech with UI

- Implement `AVSpeechSynthesizerDelegate` for highlight, progress, interruptions.
- Expose pause/continue/stop via `pauseSpeaking(at:)`, `continueSpeaking()`, `stopSpeaking(at:)`.

### 7. Testing

- Verify per locale, audio route (speaker, headphones).
- Test on-device path for low connectivity.
- Check VoiceOver and assistive speech behavior.

## Conversation design

Dictation mode supports multi-turn conversation: user speaks → system processes → system speaks (TTS) → user speaks again. Chain turns by managing boundaries.

**End-of-speech detection**: `SFSpeechRecognizer` does not auto-detect when the user stops. `isFinal` only becomes true after ~60s silence. You must decide when to call `endAudio()`:

- **Explicit action**: User taps "Done" or "Stop". Call `endAudio()` and process.
- **Silence timer**: On each partial result, reset a timer (e.g. 1.5–2s). When it fires with no new results, call `endAudio()`. More conversational; tune delay to avoid cutting off or waiting too long.

## Examples

### Voice roles and permission

```swift
import Speech

enum VoiceMode { case command; case dictation }

struct VoiceTurnContext { let mode: VoiceMode; let transcript: String }

func requestSpeechAuthorization(completion: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void) {
    SFSpeechRecognizer.requestAuthorization { status in
        DispatchQueue.main.async { completion(status) }
    }
}
```

### Live recognition (full pipeline)

```swift
import AVFoundation
import Speech

final class LiveSpeechRecognizer: NSObject, ObservableObject {
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    @Published var partialText: String = ""
    @Published var finalText: String = ""

    func startListening() throws {
        recognitionTask?.cancel()
        recognitionTask = nil
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        request.contextualStrings = ["Big Mac", "large fries", "Coke Zero"]
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [request] buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result = result {
                self.partialText = result.bestTranscription.formattedString
                if result.isFinal {
                    self.finalText = self.partialText
                    self.stopListening()
                }
            }
            if error != nil { self.stopListening() }
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask = nil
    }
}
```

### TTS prompting with delegate

```swift
import AVFoundation

final class SpeechPrompter: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speakOrderIntro() {
        ["I'll help you place your order.",
         "You can say things like 'I want a Big Mac and large fries'.",
         "When you're ready, start speaking."]
            .map(makeUtterance)
            .forEach { synthesizer.speak($0) }
    }

    private func makeUtterance(_ text: String) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        u.preUtteranceDelay = 0.1
        u.postUtteranceDelay = 0.2
        return u
    }

    func pause() { synthesizer.pauseSpeaking(at: .immediate) }
    func resume() { synthesizer.continueSpeaking() }
    func stop() { synthesizer.stopSpeaking(at: .immediate) }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        // Highlight matching range in on-screen text
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Enable mic button or advance UI state
    }
}
```

## Notes

- For long-form/distant-audio: prefer `SpeechAnalyzer`/`SpeechTranscriber` where available.
- Use `SFCustomLanguageModelData` and weighted phrases for domain vocabulary.
