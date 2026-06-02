---
name: remotion-programmatic-video
description: >-
  Install + ship Remotion v4 at staff depth: scaffold (create-video), brownfield Next.js, bundled FFmpeg,
  Studio, programmatic render (bundle/selectComposition/renderMedia), <Player>, @remotion/transitions,
  TikTok captions (@remotion/captions + whisper), Lambda at scale, data-driven batch, AI-clip compositing.
  Use to install Remotion or render React → MP4.
---

# Remotion — Install & Programmatic Video

**Mandate:** use Remotion when pixels must be **exact and reproducible** — legible text, brand color, charts,
legal lines, captions, and N localized variants. It's React that renders to MP4 deterministically. Generative
AI owns the *scene*; Remotion owns *everything that must be correct*. Don't fight diffusion to spell a price.

Official docs: https://www.remotion.dev/docs/ · current line: **v4.x**

## When to use / NOT use

- **Use** for branded overlays, data-driven/personalized video, captions, end cards, and CI-rendered variants.
- **NOT** for photoreal motion/B-roll (that's generative — Veo/Kling/Sora). Compose: AI clip + Remotion layer.

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| **Node.js** | 18+ recommended (min 16) |
| **Package manager** | npm / pnpm / yarn / bun |
| **FFmpeg** | **v4+ bundles FFmpeg + FFprobe** — no manual install on macOS/Win/Linux x64 |
| **OS** | macOS, Windows x64, Linux (glibc ≥ 2.35; Alpine/nixOS unsupported) |

## Install — new project (recommended)

```bash
npx create-video@latest
```

1. Choose package manager. 2. Pick a template (**Hello World** first time, **Next.js** for app integration).
3. Enter the folder and start Studio:

```bash
cd my-video
npm install          # if the scaffold didn't
npm run dev          # Remotion Studio: preview + timeline + props editor
```

Verify + first render:

```bash
npx remotion versions
npx remotion compositions src/index.ts                 # list composition IDs
npx remotion render src/index.ts HelloWorld out/hello.mp4
```

> Template IDs differ (`HelloWorld`, `MyComp`, …) — check `src/Root.tsx` for `<Composition id="…">`.

## Install — existing Next.js / React app (brownfield)

Docs: https://www.remotion.dev/docs/brownfield

```bash
npm install remotion @remotion/cli @remotion/bundler @remotion/renderer @remotion/player
npm install react react-dom          # peers, if missing
```

```json
{ "scripts": {
  "remotion": "remotion studio",
  "render": "remotion render src/remotion/index.ts MyComp out/video.mp4"
}}
```

Create `src/remotion/Root.tsx` with your `<Composition>` entries and point Studio at it. **Optional Tailwind in frames:**

```bash
npm install tailwindcss @tailwindcss/postcss
```

Import your global CSS in the Remotion entry; pull brand tokens from `color-design-master` / `tailwind-master`.

## FFmpeg (v4+ — automatic)

Remotion downloads/bundles `ffmpeg` + `ffprobe` into `node_modules` on first render. For CI/servers with no prior render:

```bash
npx remotion install ffmpeg
npx remotion install ffprobe
```

Run FFmpeg with **no system install**, and re-encode AI clips to Remotion-friendly CFR 30 H.264/AAC:

```bash
npx remotion ffmpeg -i veo-shot.mp4 -c:v libx264 -c:a aac -vsync cfr -r 30 public/shots/01.mp4
```

Put assets in **`public/`**; reference with `staticFile("shots/01.mp4")`. Avoid `#`/`?` in filenames (breaks bundler paths).

## Project layout

```
my-video/
├── src/{Root.tsx, index.ts, MyComp.tsx}   # Root registers compositions; index is the entry
├── public/                                # videos, images, fonts, captions.json
├── remotion.config.ts                     # optional
└── out/                                   # rendered MP4s
```

---

## Composition + typed props (zod)

```tsx
// src/Root.tsx
import { Composition } from "remotion";
import { z } from "zod";
import { Promo } from "./Promo";

export const promoSchema = z.object({ title: z.string(), price: z.string(), logo: z.string() });

export const RemotionRoot = () => (
  <Composition
    id="Promo" component={Promo} schema={promoSchema}
    durationInFrames={450} fps={30} width={1080} height={1920}
    defaultProps={{ title: "مرحبا", price: "99 AED", logo: "brand/logo.svg" }}
  />
);
```

`schema` gives Studio a typed props editor and validates `--props` at render. Use `calculateMetadata()` to derive duration/dimensions from props (e.g. match an input clip's length).

## Composite AI footage + crisp overlay

```tsx
import { AbsoluteFill, OffthreadVideo, Img, staticFile, useCurrentFrame, interpolate } from "remotion";

export const Promo: React.FC<{title:string; price:string; logo:string}> = ({ title, price, logo }) => {
  const f = useCurrentFrame();
  const fade = interpolate(f, [0, 15], [0, 1], { extrapolateRight: "clamp" });
  return (
    <AbsoluteFill>
      <OffthreadVideo src={staticFile("shots/01.mp4")} />        {/* OffthreadVideo, NOT <video> */}
      <AbsoluteFill style={{ justifyContent: "flex-end", alignItems: "flex-end", padding: 64, opacity: fade }}>
        <Img src={staticFile(logo)} style={{ width: 160 }} />
        <h1 style={{ fontSize: 84, color: "#fff", fontFamily: "Inter" }}>{title}</h1>
        <p style={{ fontSize: 56, color: "#FFD166" }}>{price}</p>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
```

Use `OffthreadVideo` (not HTML `<video>`) for frame-accurate, deterministic decoding during render.

## Transitions (`@remotion/transitions`)

```tsx
import { TransitionSeries, linearTiming, springTiming } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import { wipe } from "@remotion/transitions/wipe";

<TransitionSeries>
  <TransitionSeries.Sequence durationInFrames={60}><SceneA /></TransitionSeries.Sequence>
  <TransitionSeries.Transition timing={springTiming({ config: { damping: 200 } })} presentation={fade()} />
  <TransitionSeries.Sequence durationInFrames={90}><SceneB /></TransitionSeries.Sequence>
  <TransitionSeries.Transition timing={linearTiming({ durationInFrames: 12 })} presentation={wipe()} />
  <TransitionSeries.Sequence durationInFrames={60}><SceneC /></TransitionSeries.Sequence>
</TransitionSeries>
```

## TikTok-style captions (auto-transcribe → animate)

Transcribe locally with Whisper.cpp, then render word-highlight pages. Install: `npx remotion add @remotion/captions`.

```ts
// scripts/transcribe.ts — token-level timestamps for word highlighting
import path from "path"; import fs from "fs";
import { installWhisperCpp, downloadWhisperModel, transcribe, toCaptions } from "@remotion/install-whisper-cpp";
const to = path.join(process.cwd(), "whisper.cpp");
await installWhisperCpp({ to, version: "1.5.5" });
await downloadWhisperModel({ model: "medium.en", folder: to });
// ffmpeg -i vo.mp3 -ar 16000 vo.wav -y   (Whisper wants 16kHz wav)
const out = await transcribe({ model: "medium.en", whisperPath: to, whisperCppVersion: "1.5.5",
  inputPath: "public/vo.wav", tokenLevelTimestamps: true });
fs.writeFileSync("public/captions.json", JSON.stringify(toCaptions({ whisperCppOutput: out }).captions));
```

```tsx
// CaptionPage.tsx — highlight the active word
import { AbsoluteFill, useCurrentFrame, useVideoConfig } from "remotion";
import { createTikTokStyleCaptions, type Caption, type TikTokPage } from "@remotion/captions";

const HIGHLIGHT = "#39E508";
export const Page: React.FC<{ page: TikTokPage }> = ({ page }) => {
  const { fps } = useVideoConfig();
  const nowMs = page.startMs + (useCurrentFrame() / fps) * 1000;
  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
      <div style={{ fontSize: 80, fontWeight: 700, whiteSpace: "pre", textAlign: "center" }}>
        {page.tokens.map((t) => (
          <span key={t.fromMs} style={{ color: t.fromMs <= nowMs && t.toMs > nowMs ? HIGHLIGHT : "#fff" }}>{t.text}</span>
        ))}
      </div>
    </AbsoluteFill>
  );
};
// const { pages } = createTikTokStyleCaptions({ captions, combineTokensWithinMilliseconds: 1200 });
```

`whiteSpace: "pre"` preserves the leading spaces the API embeds in `token.text`. For **Arabic captions**, set `direction: "rtl"` and a font with Arabic glyphs (e.g. `@remotion/google-fonts/Cairo`).

## Audio

```tsx
import { Audio, staticFile } from "remotion";
<Audio src={staticFile("music.mp3")} startFrom={0} endAt={150} volume={0.25} />   {/* duck under VO */}
```

## Programmatic render (server-side, CI)

```ts
// render.mjs — bundle once, render many
import { bundle } from "@remotion/bundler";
import { selectComposition, renderMedia } from "@remotion/renderer";

const serveUrl = await bundle({ entryPoint: "./src/index.ts" });
const inputProps = { title: "مرحبا", price: "99 AED", logo: "brand/logo.svg" };
const composition = await selectComposition({ serveUrl, id: "Promo", inputProps });
await renderMedia({
  composition, serveUrl, codec: "h264", outputLocation: "out/promo.mp4",
  inputProps, crf: 18, audioCodec: "aac",
});
```

Pass the **same `inputProps`** to `selectComposition` and `renderMedia` (props can change duration via `calculateMetadata`). Use `getCompositions()` to enumerate. `inputProps` is optional in v4, **required in v5** — always pass it.

CLI batch (per-row props):

```bash
npx remotion render src/index.ts Promo out/promo_ar.mp4 --props='{"title":"مرحبا","price":"99"}'
```

```ts
for (const row of rows) {
  const comp = await selectComposition({ serveUrl, id: "Promo", inputProps: row });
  await renderMedia({ composition: comp, serveUrl, codec: "h264", outputLocation: `out/${row.id}.mp4`, inputProps: row });
}
```

## Embed in your app — `<Player>`

```tsx
import { Player, type PlayerRef } from "@remotion/player";
import { useRef } from "react";

const ref = useRef<PlayerRef>(null);
<Player ref={ref} component={Promo} durationInFrames={450} fps={30}
  compositionWidth={1080} compositionHeight={1920} inputProps={props}
  controls numberOfSharedAudioTags={5} style={{ width: "100%" }} />;
// ref.current?.play(); ref.current?.getCurrentFrame();
```

`numberOfSharedAudioTags` pre-mounts silent audio tags so audio plays under iOS Safari autoplay policy. The Player previews in-browser; it does **not** render — that's `renderMedia`/Lambda.

## Lambda — render at scale

```bash
npm install @remotion/lambda
```

```ts
import { deploySite, deployFunction, renderMediaOnLambda, getRenderProgress } from "@remotion/lambda";
// 1) deploy code + function (once / per release)
const { functionName } = await deployFunction({ region: "us-east-1", timeoutInSeconds: 240, memorySizeInMb: 2048, createCloudWatchLogGroup: true });
const { serveUrl } = await deploySite({ entryPoint: "./src/index.ts", bucketName: undefined, region: "us-east-1", siteName: "promo" });
// 2) fire a render
const { renderId, bucketName } = await renderMediaOnLambda({ region: "us-east-1", functionName, serveUrl, composition: "Promo", codec: "h264", inputProps });
// 3) poll progress
const p = await getRenderProgress({ renderId, bucketName, functionName, region: "us-east-1" }); // p.done, p.outputFile
```

Use Lambda for **100+ variants** or parallel renders; it's overkill (and AWS setup overhead) for a handful of local ads. Import from `@remotion/lambda/client` inside serverless handlers to avoid bundling the full SDK.

## CI (GitHub Actions)

```yaml
- run: npx remotion install ffmpeg && npx remotion install ffprobe
- run: npx remotion render src/index.ts Promo out/final.mp4 --props='${{ toJSON(inputs.props) }}'
- uses: actions/upload-artifact@v4
  with: { name: promo, path: out/final.mp4 }
```

## Install troubleshooting

| Problem | Fix |
|---------|-----|
| `ffmpeg` not found (old v3) | `npm i @remotion/cli@latest @remotion/renderer@latest` |
| Render fails on Linux CI | install libc deps; run `npx remotion install ffmpeg` before render |
| Asset not found in CLI render | move to `public/` + `staticFile()` (no `/src` relative paths) |
| Unsupported codec from AI clip | re-encode via `npx remotion ffmpeg` → H.264/AAC CFR 30 |
| `#`/`?` in filename | rename — breaks bundler paths |
| Fonts not loading in render | `@remotion/google-fonts` (don't rely on `<link>` / system fonts) |

## Performance / cost / reliability

- **Render is CPU/RAM-bound.** Lambda concurrency × memory drives both speed and AWS $; size `memorySizeInMb` to the composition.
- **Bundle once, render many** — `bundle()` is the slow step; reuse `serveUrl` across a batch.
- **Determinism:** never use `Date.now()`/`Math.random()` in components — use `useCurrentFrame()`/`random()` from remotion, or renders won't reproduce.
- Renders can change across Remotion versions (even patches) — **pin the version** for client-reproducible output.

## Security

- Don't ship secrets into `public/` or `inputProps` (they're embedded in the bundle/output).
- Lambda IAM: least-privilege role; scope the S3 bucket; enable CloudWatch logs for audit.

## Agent checklist

```
- [ ] Installed via create-video (new) or brownfield deps (existing Next.js)
- [ ] FFmpeg bundled (npx remotion ffmpeg works) — no system ffmpeg assumed
- [ ] AI clips re-encoded to H.264/AAC CFR 30 in public/
- [ ] Props typed with zod schema; inputProps passed to BOTH selectComposition + renderMedia
- [ ] No Date.now()/Math.random() in components (deterministic render)
- [ ] Captions: token-level whisper → createTikTokStyleCaptions; RTL+Arabic font if needed
- [ ] Lambda only for 100+ variants; version pinned for reproducibility
```

## Anti-patterns

- HTML `<video>`/`<img>` instead of `OffthreadVideo`/`Img` → flicker, wrong frames.
- Asking AI to render the price/logo, then "fixing" in Remotion — generate scene in AI, text in Remotion from the start.
- One blanket `"use client"` Next.js boundary dragging the Remotion bundle into the client.
- Re-bundling per variant in a batch (slow) — bundle once, loop renders.

## References

- SSR render: https://www.remotion.dev/docs/ssr · `renderMedia`: https://www.remotion.dev/docs/renderer/render-media
- Captions: https://www.remotion.dev/docs/captions/displaying · Whisper: https://www.remotion.dev/docs/install-whisper-cpp/
- Lambda: https://www.remotion.dev/docs/lambda · Player: https://www.remotion.dev/docs/player/player

## Related

`video-ffmpeg-post-production`, `video-ai-production-workflow`, `ai-video-audio-voiceover`, `tailwind-master`, `color-design-master`
