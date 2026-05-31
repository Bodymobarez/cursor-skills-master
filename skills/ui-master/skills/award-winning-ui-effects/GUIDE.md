---
name: award-winning-ui-effects
description: >-
  Create award-winning, innovative, never-seen-before UI — Awwwards/FWA-tier
  visuals and motion. Use when the user wants cutting-edge, jaw-dropping, original
  interfaces: WebGL/shaders, 3D, mesh gradients, glassmorphism/aurora, scroll-driven
  storytelling, advanced micro-interactions, and generative visuals. Covers the
  modern stack, signature techniques, and performance.
---

# Award-Winning UI Effects (Awwwards-tier, original)

Build interfaces that win awards and feel like nothing seen before — but stay fast and usable.
Innovation = **a bold concept + signature motion + flawless craft**, not effect soup.

## Creative direction first (don't skip)
- Pick **one signature idea** (a hero interaction, a material, a transition) and make it
  unforgettable; everything else supports it.
- Decide a **mood/visual language**: editorial, brutalist, futuristic/HUD, organic/fluid,
  glass/aurora, kinetic-typographic, dimensional/3D.
- Originality: combine two unexpected techniques (e.g. shader gradient + kinetic type + physics
  scroll). "Never seen before" comes from combination + execution.

## The modern stack (2026)

| Need | Tool |
|------|------|
| 3D / WebGL | **Three.js + React Three Fiber + Drei**, or **OGL** (lightweight) |
| Shaders | GLSL fragment/vertex; `@react-three/fiber` shaderMaterial; TSL |
| GPU 2D effects | **PixiJS**, shader backgrounds, WebGPU |
| Motion / orchestration | **GSAP** (+ ScrollTrigger, Flip), **Framer Motion** |
| Scroll | **Lenis** (smooth scroll) + ScrollTrigger; scroll-driven CSS animations |
| Physics | Rapier / Matter.js for playful, tactile motion |
| Native transitions | **View Transitions API** (page/element morphs) |

## Signature techniques (high-end toolbox)
- **Mesh / aurora gradients**: animated multi-stop gradients via shader or layered conic/radial +
  blur; subtle grain overlay to kill banding (instant premium look).
- **Glassmorphism done right**: `backdrop-filter` blur + saturation + 1px light border +
  inner highlight + soft shadow (not flat translucent boxes).
- **WebGL hero**: shader background (flow fields, fluid, noise displacement), or 3D product with
  R3F + environment lighting + subtle parallax.
- **Kinetic typography**: variable-font weight/width animated on scroll/hover; text split into
  chars (SplitType) with staggered reveal.
- **Scroll storytelling**: pin sections, scrub animations to scroll progress, image sequences,
  reveal-on-enter with stagger; horizontal scroll galleries.
- **Magnetic / cursor effects**: magnetic buttons, custom cursor, hover distortion (shader),
  spotlight/mask follow.
- **Page transitions**: View Transitions API or FLIP morphs between routes for seamless flow.
- **Micro-interactions**: spring physics on press, elastic drag, morphing icons, confetti/particles
  on success — small, delightful, purposeful.
- **3D + depth**: parallax layers, tilt (gyro/mouse), depth-of-field, real-time shadows.

## Craft details that read as "expensive"
- Spring/eased motion (no linear); orchestrated **staggers**; consistent easing language.
- Grain/noise texture, subtle vignette, light leaks, chromatic aberration — used sparingly.
- Depth via layered shadows + blur + scale; light source consistency.
- Sound design (optional, opt-in) for premium product reveals.
- Ultra-crisp rendering (pair with `ultra-hd-visual-rendering`) — effects must be sharp, not muddy.

## Performance (non-negotiable — awards require 60fps)
```
- [ ] Animate only transform/opacity; promote with will-change; avoid layout thrash
- [ ] WebGL at devicePixelRatio but cap (e.g. min(dpr,2)) for heavy scenes; pause offscreen
- [ ] Lazy-init heavy 3D/shaders; code-split; preload key assets
- [ ] Throttle scroll/mouse with rAF; use IntersectionObserver
- [ ] Compress textures (KTX2/Basis), draco/meshopt for 3D models
- [ ] Target 60fps mid device; degrade gracefully on low-end/mobile
```

## Accessibility & restraint (separates pros from show-offs)
- Honor `prefers-reduced-motion` — provide a calm fallback (no parallax/auto-motion).
- Keep content readable/usable: effects never block interaction, focus, or text contrast.
- Keyboard + screen-reader paths work regardless of visual flourish.

## Checklist
```
- [ ] One signature concept + defined visual language/mood
- [ ] Signature technique (shader/3D/kinetic/scroll story) executed flawlessly
- [ ] Spring/eased orchestrated motion with staggers; consistent easing
- [ ] Grain/depth/lighting craft details; ultra-crisp rendering
- [ ] 60fps verified; reduced-motion + a11y fallbacks
- [ ] Mobile/low-end graceful degradation
```

## Anti-patterns
- "Effect soup": many unrelated effects, no concept → cheap and chaotic.
- Janky scroll/3D (animating layout props, ignoring DPR caps, no offscreen pause).
- Ignoring reduced-motion / breaking keyboard & contrast for visuals.
- Heavy WebGL with no loading/degradation → blank screen on mobile.
- Trend-copying without an original combination — looks like everyone else.
