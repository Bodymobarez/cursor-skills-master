---
name: camera-ai-vision
description: >-
  Full camera handling and AI visual analytics. Use for accessing the camera
  (web/mobile), capturing photo/video, live streams, and analyzing frames with AI —
  object/face detection, OCR, barcode/QR scanning, pose, segmentation, or
  vision-LLM understanding. Covers getUserMedia, on-device vs cloud inference,
  real-time pipelines, and privacy.
---

# Camera + AI Vision

Access the camera and run AI analytics on the feed — detection, OCR, scanning, and
vision-LLM understanding. Two layers: **(1) capture** and **(2) analyze**.

## 1. Capture

**Web (getUserMedia):**
```js
const stream = await navigator.mediaDevices.getUserMedia({
  video: { facingMode: "environment", width: { ideal: 1280 }, height: { ideal: 720 } },
  audio: false,
});
videoEl.srcObject = stream;
// grab a frame:
const c = document.createElement("canvas");
c.width = videoEl.videoWidth; c.height = videoEl.videoHeight;
c.getContext("2d").drawImage(videoEl, 0, 0);
const blob = await new Promise(r => c.toBlob(r, "image/jpeg", 0.85));
// stop: stream.getTracks().forEach(t => t.stop());
```
- Requires **HTTPS** (or localhost). Handle permission denial gracefully.
- Enumerate/switch cameras with `enumerateDevices`; use `facingMode` for front/back.
- **Mobile:** Expo `expo-camera` / React Native Vision Camera (with frame processors for real-time ML).

## 2. Analyze — choose on-device vs cloud

| Approach | Use | Tools |
|----------|-----|-------|
| **On-device, real-time** | Live overlays, privacy, no network | TensorFlow.js, **MediaPipe Tasks** (face/hand/pose, object det, segmentation), ONNX Runtime Web, transformers.js, WebGPU |
| **Cloud / vision-LLM** | Rich understanding, captioning, Q&A, complex scenes | GPT-4o/GPT-5 vision, Gemini, Claude vision, fal.ai-hosted models |
| **Specialized API** | OCR, faces, labels | Google Vision, AWS Rekognition, Azure Vision |

### Task → tool

| Task | Recommended |
|------|-------------|
| Object detection (live) | MediaPipe Object Detector / YOLO (ONNX/TFJS) |
| Face detection/landmarks | MediaPipe Face Landmarker |
| Pose / hands | MediaPipe Pose / Hands |
| Segmentation / background removal | MediaPipe Selfie Segmentation / SAM |
| **OCR** (text) | Tesseract.js (offline), or cloud Vision; see `vision-ocr` skill |
| **Barcode / QR scan** | `@zxing/library` / BarcodeDetector API (see `qr-code-generation`, `gs1-barcodes`) |
| Scene understanding / "what is this?" | Vision LLM with the captured frame |

### Vision-LLM on a captured frame
```js
// send base64 JPEG to a vision model
{ role: "user", content: [
  { type: "text", text: "What products are on this shelf? Return JSON." },
  { type: "image_url", image_url: { url: `data:image/jpeg;base64,${b64}` } } ] }
```

## 3. Real-time pipeline (do it efficiently)

```
video frame → throttle (e.g. analyze 5–10 fps, not 60) → downscale → model → draw overlay
```
- **Don't run the model on every frame.** Throttle; reuse the last result between inferences.
- Downscale frames before inference (e.g. 320–640px) for speed.
- Run heavy models in a **Web Worker / OffscreenCanvas**; use **WebGPU/WebGL** backend.
- For cloud calls, sample sparse frames (e.g. 1/sec) — never stream every frame.

## Checklist
```
- [ ] HTTPS + permission flow (request, denied fallback, camera switch)
- [ ] Decide on-device (privacy/real-time) vs cloud (understanding)
- [ ] Throttle + downscale frames; worker + GPU backend for live inference
- [ ] Draw overlays aligned to source resolution (scale boxes correctly)
- [ ] Stop tracks on unmount; release camera
- [ ] Privacy: consent, on-device when possible, don't store frames without permission
```

## Anti-patterns
- Running inference on every frame at full resolution → frozen UI.
- Forgetting HTTPS / not stopping tracks (camera light stays on).
- Sending continuous video to a cloud vision API (cost + latency); sample instead.
- Storing/transmitting biometric/face data without consent and a clear policy.
