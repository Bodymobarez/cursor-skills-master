---
name: ai-video-api-fal-runway
description: >-
  Production AI video API integration: fal.ai (Veo 3.1, Kling 2.5, Sora 2, Luma, Wan) + Runway Gen-4.5,
  with the queue API (submit/status/result), verified ED25519 webhook signature checks, server-side key
  handling, exponential-backoff retries, idempotency, and per-job cost logging. Use to actually generate.
---

# AI Video API Integration (fal.ai + Runway)

**Mandate:** generation is **async, metered, and fallible**. Use the **queue + webhooks** (not blocking calls)
for anything batch, **verify every webhook signature**, keep keys **server-side only**, and **log $ per job**.
A naive `subscribe()` in a request handler will time out, leak keys to the client, or silently double-bill on retry.

## When to use / NOT use

- **Use** to wire real generation: one model or many, single clip or batch pipeline.
- **NOT** to choose *which* model (`ai-video-models-selection`) or write the prompt (`ai-video-cinematic-prompts`).

## Environment & key hygiene

```bash
# .env.local — server-side ONLY. Never NEXT_PUBLIC_*, never in client bundles.
FAL_KEY=...
RUNWAYML_API_SECRET=...
GEMINI_API_KEY=...          # if calling Veo via Google directly instead of fal
```

Keys live in server runtime/secret manager. Client → your API route → provider. A leaked `FAL_KEY` is a metered-spend incident.

## fal.ai — two call modes

| Mode | API | Use |
|------|-----|-----|
| Blocking | `fal.subscribe(id, …)` | scripts, ≤1–2 clips, you can wait |
| Queue + webhook | `fal.queue.submit` → webhook / `fal.queue.status` / `fal.queue.result` | batch, web apps, anything >~60s |

### Python (`pip install fal-client`)

```python
import os, fal_client
os.environ["FAL_KEY"] = os.environ["FAL_KEY"]

def on_update(update):
    if isinstance(update, fal_client.InProgress):
        for log in update.logs: print(log["message"])

result = fal_client.subscribe(
    "fal-ai/veo3.1",
    arguments={
        "prompt": "Cinematic slow dolly on a rain-soaked Dubai street at night, neon reflections, 35mm.",
        "aspect_ratio": "9:16", "duration": "8s", "resolution": "1080p",
        "generate_audio": True, "seed": 4412, "safety_tolerance": "4",
    },
    with_logs=True, on_queue_update=on_update,
)
video_url = result["video"]["url"]   # download immediately; fal URLs are temporary
```

### Node / TypeScript (`npm i @fal-ai/client`)

```ts
import { fal } from "@fal-ai/client";
fal.config({ credentials: process.env.FAL_KEY! });

const result = await fal.subscribe("fal-ai/kling-video/v2.5-turbo/pro/image-to-video", {
  input: { prompt, image_url: refUrl, duration: "5", aspect_ratio: "9:16", cfg_scale: 0.5 },
  logs: true,
  onQueueUpdate: (u) => u.status === "IN_PROGRESS" && u.logs.forEach((l) => console.log(l.message)),
});
const url = result.data.video.url;
```

### Queue (recommended for batch)

```ts
// 1) submit — returns immediately
const { request_id } = await fal.queue.submit("fal-ai/veo3.1", {
  input: { prompt, aspect_ratio: "9:16", duration: "8s" },
  webhookUrl: "https://api.example.com/webhooks/fal",   // fal POSTs the result here
  priority: "normal",
});
// 2) (or) poll: IN_QUEUE → IN_PROGRESS → COMPLETED
const status = await fal.queue.status("fal-ai/veo3.1", { requestId: request_id, logs: true });
// 3) fetch the result when COMPLETED
const done = await fal.queue.result("fal-ai/veo3.1", { requestId: request_id });
```

## Webhooks — verify the signature (NON-NEGOTIABLE)

fal signs webhooks with **ED25519**. Reject anything that fails. Webhook `status` is `"OK"` | `"ERROR"`
(distinct from queue states). Return `200` fast; dedupe on `request_id` (fal may retry).

```ts
// app/api/webhooks/fal/route.ts  (Next.js)
import sodium from "libsodium-wrappers";
import { createHash } from "crypto";

let jwks: { keys: { x: string }[] } | null = null;   // cache ≤ 24h
async function getKeys() {
  if (!jwks) jwks = await (await fetch("https://rest.fal.ai/.well-known/jwks.json")).json();
  return jwks!;
}

export async function POST(req: Request) {
  await sodium.ready;
  const h = req.headers;
  const reqId = h.get("x-fal-webhook-request-id"); const userId = h.get("x-fal-webhook-user-id");
  const ts = h.get("x-fal-webhook-timestamp");      const sigHex = h.get("x-fal-webhook-signature");
  const body = Buffer.from(await req.arrayBuffer());
  if (!reqId || !userId || !ts || !sigHex) return new Response("missing headers", { status: 401 });

  if (Math.abs(Math.floor(Date.now() / 1000) - parseInt(ts, 10)) > 300)   // replay window
    return new Response("stale", { status: 401 });

  const message = Buffer.from([reqId, userId, ts, createHash("sha256").update(body).digest("hex")].join("\n"));
  const sig = Buffer.from(sigHex, "hex");
  const ok = (await getKeys()).keys.some((k) =>
    sodium.crypto_sign_verify_detached(sig, message, Buffer.from(k.x, "base64url")));
  if (!ok) return new Response("bad signature", { status: 401 });

  const payload = JSON.parse(body.toString());      // { request_id, status: "OK"|"ERROR", payload }
  if (await alreadyHandled(payload.request_id)) return new Response("ok", { status: 200 }); // idempotent
  if (payload.status === "OK") await persist(payload.request_id, payload.payload.video.url);
  return new Response("ok", { status: 200 });
}
```

Python uses **PyNaCl** (`nacl.signing.VerifyKey`) with the same message construction.

## Next.js API route (server-side generation)

```ts
// app/api/generate/route.ts — never expose FAL_KEY to the browser
import { fal } from "@fal-ai/client";
fal.config({ credentials: process.env.FAL_KEY! });

export async function POST(req: Request) {
  const { prompt, aspect_ratio = "9:16", model = "fal-ai/veo3.1" } = await req.json();
  const { request_id } = await fal.queue.submit(model, {
    input: { prompt, aspect_ratio, duration: "8s" },
    webhookUrl: `${process.env.PUBLIC_URL}/api/webhooks/fal`,
  });
  return Response.json({ request_id });   // client polls your DB / SSE, not fal directly
}
```

## Runway (direct API + SDK)

```python
import os, time, runwayml
client = runwayml.RunwayML(api_key=os.environ["RUNWAYML_API_SECRET"])

task = client.image_to_video.create(           # omit prompt_image for text-to-video
    model="gen4.5", prompt_image="https://cdn.example.com/ref.jpg",
    prompt_text="Slow push-in, golden hour, shallow depth of field", ratio="1280:720", duration=5,
)
while task.status not in ("SUCCEEDED", "FAILED"):
    time.sleep(5); task = client.tasks.retrieve(task.id)
if task.status == "FAILED": raise RuntimeError(task.failure)
url = task.output[0]
```

Raw HTTP needs `X-Runway-Version: 2024-11-06` and `Authorization: Bearer $RUNWAYML_API_SECRET`.

## Retry policy (resilient, idempotent)

```ts
async function withRetry<T>(fn: () => Promise<T>, max = 3): Promise<T> {
  for (let i = 0; ; i++) {
    try { return await fn(); }
    catch (e: any) {
      const code = e?.status ?? e?.response?.status;
      if (code === 429 || code === 503) { if (i >= max) throw e; await sleep(2 ** i * 1000 + Math.random() * 500); continue; }
      if (code === 422 /* content policy */) throw e;   // don't retry — rewrite the prompt instead
      throw e;
    }
  }
}
```

| Failure | Action |
|---------|--------|
| 429 / 503 | exponential backoff + jitter, ≤3 tries |
| 422 content policy | `auto_fix:true` (Veo) once, else soften prompt; never blind-retry |
| 5xx provider down | fail over to next model in the fallback chain |
| webhook missing | reconcile via `fal.queue.status` cron — don't assume delivery |

Idempotency key = `{project}:{shot_id}:{seed}` so a retried submit/webhook never double-bills.

## Cost logging & observability

```ts
type JobLog = { ts:string; model:string; request_id:string; duration_s:number;
  resolution:string; audio:boolean; est_usd:number; status:"OK"|"ERROR"; latency_ms:number };
await db.costs.insert(log);   // dashboard: spend by model/day, p95 latency, failure rate, $ per finished asset
```

Aggregate **$ per *delivered* asset** (include retries + rejects), not per successful call — that's the number that blows budgets.

## Security / policy / rights

- Keys server-side only; rotate on leak; scope per environment.
- Verify webhook signatures (above) — an unsigned endpoint lets anyone forge "completed" jobs.
- Respect provider content policy; for likeness/IP use Sora `detect_and_block_ip` and clear rights (`video-ai-production-workflow`).
- Download outputs immediately — provider URLs expire; persist to your own bucket with access controls.

## Agent checklist

```
- [ ] FAL_KEY / RUNWAYML_API_SECRET server-side only
- [ ] Batch uses queue + webhook (not blocking subscribe in a request handler)
- [ ] Webhook signature verified (ED25519, JWKS cached ≤24h, 300s replay window)
- [ ] Retries: backoff on 429/503, no blind retry on 422, fallback model on 5xx
- [ ] Idempotency key dedupes submits + webhook deliveries
- [ ] Cost logged per job; output downloaded to own storage immediately
```

## Anti-patterns

- `fal.subscribe` inside an HTTP handler for an 8s+ render → gateway timeout.
- Calling fal/Runway from client code with the key in the bundle → spend leak.
- Trusting webhooks without signature verification or without idempotency → forgery + double-bills.
- Blind-retrying content-policy (422) failures → same rejection, more spend.

## References

- fal queue: https://fal.ai/docs/documentation/model-apis/inference/queue
- fal webhooks + signature: https://fal.ai/docs/documentation/model-apis/inference/webhooks
- Runway API: https://docs.dev.runwayml.com/guides/using-the-api/

## Related

`ai-video-models-selection`, `video-ai-production-workflow`, `ai-image-to-video-consistency`, `ai-video-audio-voiceover`
