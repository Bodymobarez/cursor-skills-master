---
name: ai-color-harmony-prompting
description: >-
  Use LLMs as a palette copilot at staff depth — never the authority. A hardened system prompt (OKLCH
  reasoning, APCA-aware), schema-constrained output (zod + structured outputs / tool use), and an
  independent validation+auto-repair harness (culori gamut + WCAG/APCA recompute) because models lie
  about hex↔oklch and contrast. Includes iteration prompts, vision input, and de-AI-slop guardrails.
---

# AI Color Harmony Prompting — Copilot, Verified

**Mandate:** the model **proposes**, your code **disposes**. LLMs are excellent at *harmony intuition*
(hue relationships, mood) and unreliable at *arithmetic* (they hallucinate hex that doesn't match their
own OKLCH, and confidently claim contrast that fails). Never ship a model's palette without recomputing
gamut and contrast yourself.

---

## When to use / when NOT to use

- **Use** to draft from a brand brief, explore directions fast, harmonize around a logo color, or generate
  N chart-series options — then validate.
- **NOT** when you already have a defined hue + harmony (just run `oklch-perceptual-palettes` directly —
  cheaper, deterministic), and **not** as the final source of truth. The model's output is an input to
  `color-artist-engineer`'s pipeline, never the export.

---

## Decision: model vs algorithm vs human

| Need | Use | Why |
|------|-----|-----|
| Exploration / "give me 5 directions for a fintech" | **LLM** | breadth, mood, naming |
| Deterministic ramp from a known hue | **algorithm** (`oklch-perceptual-palettes`) | exact, free, no hallucination |
| Final brand identity / high-stakes rebrand | **human designer** + this as draft | accountability, taste |
| Validate any of the above | **always your code** | models can't be trusted on math |

---

## System prompt (hardened — attach to any model)

```text
You are a Color Artist-Engineer. You output harmonious, accessible UI palettes for production.

REASONING:
- Reason in OKLCH: L (lightness 0–1), C (chroma 0–~0.4, hue/gamut-capped), H (hue 0–360).
- Exactly ONE primary brand hue and ONE accent hue. Neutrals: C ≤ 0.02, hue = primary hue (tinted).
- Pick a harmony explicitly: monochromatic | analogous (H±20–40) | complementary (H+180) |
  split-complementary (H+150 & H+210) | triadic. State which and why.
- Apply a chroma budget: large areas low chroma; high chroma only on the 10% accent layer.

ACCESSIBILITY:
- Every text/background pair must meet WCAG 2.2 AA: 4.5:1 body, 3:1 large/UI/non-text.
- Prefer pairs that also reach APCA Lc 75 for body text; note any that only reach Lc 60.
- Provide a *-foreground for every fill a user reads text on (primary, accent, destructive, ...).

OUTPUT:
- Return ONLY valid JSON matching the provided schema. No prose outside JSON.
- For each color give BOTH oklch (string "L C H") and hex, and ensure they are the SAME color.
- Include a contrastPairs array with your computed WCAG ratio per critical pair.
- Do NOT output a purple→pink gradient unless the brief explicitly asks for it.

If a value would fall outside the sRGB gamut, reduce chroma (not lightness) until it fits.
```

---

## Schema-constrained output (don't free-text JSON)

Use the provider's structured-output mode so the shape is guaranteed; validate semantics yourself after.

```ts
// palette.schema.ts
import { z } from "zod";

const Color = z.object({
  oklch: z.string().regex(/^[\d.]+ [\d.]+ [\d.]+$/), // "L C H"
  hex: z.string().regex(/^#[0-9a-fA-F]{6}$/),
});

export const PaletteSchema = z.object({
  harmony: z.enum(["monochromatic", "analogous", "complementary", "split-complementary", "triadic"]),
  rationale: z.string().min(20),
  colors: z.object({
    primary: Color, primaryForeground: Color,
    accent: Color, accentForeground: Color,
    background: Color, foreground: Color,
    muted: Color, mutedForeground: Color,
    border: Color,
    success: Color, warning: Color, destructive: Color,
  }),
  neutralRamp: z.array(z.object({ step: z.number(), oklch: z.string(), hex: z.string() })).length(11),
  contrastPairs: z.array(z.object({ fg: z.string(), bg: z.string(), ratio: z.number(), passAA: z.boolean() })),
});
export type Palette = z.infer<typeof PaletteSchema>;
```

```ts
// generate.ts — OpenAI structured outputs (Anthropic: equivalent via tool_use with input_schema)
import OpenAI from "openai";
import { zodResponseFormat } from "openai/helpers/zod";
import { PaletteSchema } from "./palette.schema";

const openai = new OpenAI();

export async function draftPalette(brief: string) {
  const res = await openai.chat.completions.parse({
    model: "gpt-5.1",                 // any current model with structured outputs
    temperature: 0.7,                 // some creativity for harmony, not chaos
    messages: [
      { role: "system", content: SYSTEM_PROMPT },
      { role: "user", content: brief },
    ],
    response_format: zodResponseFormat(PaletteSchema, "palette"),
  });
  return res.choices[0].message.parsed!; // shape guaranteed; semantics still unverified
}
```

---

## The validation + auto-repair harness (the actual value)

This is the part juniors skip and seniors never ship without. **Recompute everything**, fix what's
fixable, reject what isn't.

```ts
// validate.ts
import { oklch, formatHex, formatCss, clampChroma, differenceEuclidean, inGamut } from "culori";
import { checkPair } from "./contrast"; // from wcag-contrast-color-pairs
import type { Palette } from "./palette.schema";

const isRgb = inGamut("rgb");
const dist = differenceEuclidean("oklch");

export interface Finding { level: "error" | "fixed" | "warn"; msg: string; }

export function validateAndRepair(p: Palette): { palette: Palette; findings: Finding[] } {
  const findings: Finding[] = [];
  const colors = structuredClone(p.colors);

  for (const [name, c] of Object.entries(colors)) {
    const fromOklch = oklch(`oklch(${c.oklch})`);
    const fromHex = oklch(c.hex);
    if (!fromOklch || !fromHex) { findings.push({ level: "error", msg: `${name}: unparseable` }); continue; }

    // 1) Model lies #1: hex ≠ oklch. Trust the OKLCH (its stated intent); regenerate hex.
    if (dist(fromOklch, fromHex) > 0.02) {
      c.hex = formatHex(fromOklch)!;
      findings.push({ level: "fixed", msg: `${name}: hex≠oklch — regenerated hex from oklch` });
    }
    // 2) Model lies #2: out-of-gamut chroma. Clamp (preserve L+H).
    if (!isRgb(fromOklch)) {
      const safe = clampChroma(fromOklch, "oklch", "rgb");
      c.oklch = formatCss(safe)!.replace(/^oklch\(|\)$/g, "");
      c.hex = formatHex(safe)!;
      findings.push({ level: "fixed", msg: `${name}: out of sRGB — chroma clamped` });
    }
  }

  // 3) Model lies #3: claimed contrast. Recompute independently; never trust contrastPairs.
  const mustPass: Array<[keyof typeof colors, keyof typeof colors]> = [
    ["foreground", "background"], ["mutedForeground", "background"],
    ["primaryForeground", "primary"], ["accentForeground", "accent"],
  ];
  for (const [fg, bg] of mustPass) {
    const r = checkPair(colors[fg].hex, colors[bg].hex);
    if (!r.passAA) findings.push({ level: "error", msg: `${fg} on ${bg}: ${r.wcag.toFixed(2)}:1 < 4.5 (APCA Lc ${r.apcaLc.toFixed(0)})` });
  }
  return { palette: { ...p, colors }, findings };
}
```

If any `error` remains, **re-prompt** with the specific failures (below) — don't hand-patch silently, you
lose the model's harmony intent.

---

## Iteration prompts (feed findings back)

**Fix failed contrast (precise):**
```text
These pairs failed WCAG AA: {{list with measured ratios}}. Adjust ONLY the lightness (L) of the
foreground or background until each reaches ≥ 4.5:1. Do NOT change the hue (H) of the brand primary.
Return the full JSON again.
```

**Too loud:**
```text
Keep all hues (H). Reduce chroma (C) by ~20% on background, muted, and any large-area color. Leave the
accent's chroma. Re-state the contrastPairs.
```

**Too boring:**
```text
Raise the accent chroma slightly and add a split-complementary accent (primary H + 150°). Keep neutrals
calm (C ≤ 0.02). Re-check contrast.
```

**Harmonize with a logo:**
```text
Logo dominant color ≈ oklch({{L C H}}). Build an analogous palette around hue {{H}}. Derive neutrals from
that hue (not pure gray). Ensure the accent stays distinguishable under deuteranopia.
```

---

## Vision input (logo / screenshot)

```text
Analyze this image's dominant hues and emotional tone. Propose a UI palette inspired by it — do NOT copy
photographic colors 1:1. Derive neutrals from the dominant hue. Output the JSON schema; reason in OKLCH.
```

War story: vision models over-saturate (they sample the most vivid pixels). Always lower the chroma budget
on the *result* and re-clamp.

---

## De-AI-slop guardrails (reject + re-prompt if any are true)

- Purple `#8B5CF6` + pink `#EC4899` gradient cliché (unless brief is a creative/AI product).
- More than two saturated hues at large-area roles.
- `gray-400`-ish text on `gray-500`-ish background (the model's favorite illegible combo).
- Missing any `*-foreground`, or a missing/empty contrast matrix.
- All hues within ~15° (it called everything "blue" — no real accent).

---

## Cost / performance / security

- **Cache by brief hash** — identical briefs shouldn't re-bill. Palettes are deterministic enough to memo.
- **Temperature 0.6–0.8** for generation (harmony needs some creativity); **0** for repair passes.
- **Prompt-injection / PII:** brand briefs are user input. Don't interpolate them into tool-executing
  contexts; never let a brief instruct the model to ignore the accessibility rules. Strip PII before
  logging briefs.
- Bound retries (2–3) so a model that can't satisfy AA doesn't loop forever — fall back to algorithmic
  generation.

## Testing strategy

- **Golden briefs → golden palettes:** snapshot a few canonical briefs' validated output; a prompt or
  model change that regresses contrast/gamut fails CI.
- Assert the harness *catches* injected bad palettes (hex≠oklch, out-of-gamut, failing pair) — test the
  validator, not just the happy path.

## Observability / debugging

- Log every `Finding` with the brief hash. A spike in `fixed: hex≠oklch` means the model drifted (model
  update?) — your harness absorbed it, but you'll want to know.
- Persist the raw model JSON alongside the repaired version for auditing "why is this color slightly
  different from what the model said."

## Anti-patterns
- Trusting the model's `contrastPairs` (recompute, always).
- Trusting hex when it disagrees with the stated OKLCH.
- Free-text JSON instead of schema-constrained output.
- Silently hand-fixing failures instead of re-prompting (loses harmony intent).
- Shipping vision-sampled chroma without re-clamping.
- Unbounded repair retries.

## Agent checklist
```
- [ ] Hardened system prompt (OKLCH + APCA + de-slop) attached
- [ ] Output is schema-constrained (zod + structured outputs / tool use)
- [ ] hex↔oklch agreement re-derived in code (trust oklch)
- [ ] Every color gamut-clamped to sRGB independently
- [ ] All mandatory pairs' contrast RECOMPUTED (model claims ignored)
- [ ] Failures fed back as precise iteration prompts (bounded retries)
- [ ] Validated palette handed to palette-to-tokens-export (not the raw model output)
```

## References
- OpenAI Structured Outputs: https://platform.openai.com/docs/guides/structured-outputs
- Anthropic tool use (JSON schema): https://docs.anthropic.com/en/docs/build-with-claude/tool-use
- zod: https://zod.dev
- culori (gamut/contrast): https://culorijs.org/api/

## Related
`color-artist-engineer`, `oklch-perceptual-palettes`, `wcag-contrast-color-pairs`, `cvd-colorblind-safe`,
`prompt-engineering-advanced` (ai-mcp-master)
