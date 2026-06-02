---
name: 3d-render-motion-graphics
description: >-
  The "5D" engine at principal depth: real 3D + motion graphics across Blender 4.5 LTS (with bpy
  Python), Spline, and Three.js / React Three Fiber (R3F v9, WebGPU). Covers PBR materials, lighting
  (HDRI + 3-point), cameras/DOF, render settings (EEVEE Next vs Cycles), and a web-vs-offline render
  decision matrix. "5D" = photoreal depth + 3D form + cinematic light + motion — a quality bar, not a
  format. Use to produce logo treatments, product viz, and 3D motion graphics.
---

# 3D Render & Motion Graphics

## Mandate

Make real **dimensional form, light, and motion** — the engine that turns flat marks/images into the
"5D" quality bar (**photoreal depth + 3D form + cinematic light + motion**). Decide *web vs offline*
deliberately (it dictates the whole pipeline), light with intent, and use **PBR + linear color** so
materials are physically plausible. "5D" is a bar, not a file format.

## When to use / NOT use

- **Use** for: 3D logo treatments (metal/glass/extrude), product viz, abstract motion-graphics loops,
  3D titles, real-time web hero scenes, and CG passes feeding `cinematic-5d-video-production`.
- **NOT** for: 2D vector logos (→ `logo-5d-pro` — build the mark there first), raster key art (→
  `image-5d-pro`), or color/LUT finishing (→ `color-grading-cinematic`). For full AI-generated motion
  video, route to `video-ai-master`.

## Mental model — pick the runtime FIRST

```
            ┌── WEB / REAL-TIME ──→ Three.js / R3F (WebGPU/WebGL)  · interactive, 60fps, ships in a page
TARGET ─────┤
            └── OFFLINE / FILM ───→ Blender (Cycles/EEVEE Next), Spline export · pixel-exact, render farm
```

Everything downstream (materials authoring, poly budget, lighting, output) branches off this choice.
Authoring the wrong runtime is the #1 wasted-week mistake.

## Web vs offline — decision matrix

| Axis | Three.js / R3F (real-time) | Blender (offline) | Spline (hybrid) |
|------|----------------------------|-------------------|-----------------|
| **Best for** | interactive web, configurators, hero scenes | film/ad shots, product viz, hero stills | quick web 3D, designer-friendly, no-code |
| **Quality ceiling** | high (WebGPU/TSL, PBR, RT-ish) | photoreal (Cycles path-tracing) | good, stylized |
| **Frame budget** | **must hit 60fps** on target device | minutes/frame OK | real-time |
| **Output** | live canvas / WebGL | EXR/PNG sequence → comp/grade | live embed or export |
| **Pipeline cost** | dev time, perf budget | render time, farm/Lambda | low; less control |
| **When to choose** | the 3D *is* the web experience | the 3D is a *shot* in a video/still | designer ships fast, control secondary |

Rule: **if it plays in a browser and reacts to the user → R3F. If it's a frame in a film/ad → Blender.**
Don't render a static hero in WebGL (waste of client GPU) or try to ship a path-traced scene live.

## Lighting (same grammar as the camera skills)

- **HDRI / IBL**: a single good HDRI gives realistic ambient + reflections instantly — the fastest
  path to "photoreal". Rotate it to place the key highlight; dial intensity.
- **3-point as the backbone**: **key** (main, directional, sets the ratio), **fill** (softens
  shadow, lower intensity/cooler), **rim/back** (separates subject from bg). Add practicals for mood.
- **Ratios + color temp** create drama: e.g. key:fill 4:1, warm key / cool fill. Soft (large source)
  = beauty/product; hard (small source) = drama/contrast.
- **Light is linear**: author and render in linear/scene-referred space; apply the view transform
  (AgX in Blender 4.x, or Filmic) at the end — never light against a display-gamma background.

## PBR materials (metal/roughness — the standard)

- **Base color** (albedo, no baked light), **metalness** (0 dielectric / 1 metal — avoid in-between),
  **roughness** (the single most important knob for realism), **normal** (surface detail),
  **height/AO**, plus **transmission/IOR** for glass and **emission** for glow.
- **Metal** = metalness 1, color tints the *reflection*, roughness sells brushed vs polished.
- **Glass** = transmission 1, IOR ~1.45 (glass) / 2.4 (diamond), low roughness, thin/thick as needed.
- Keep textures **linear for data maps** (normal/roughness/metal) and **sRGB for color maps** — mixing
  these up is the most common "why does my material look wrong" bug.

## Blender 4.5 LTS — `bpy` Python (headless, reproducible, copy/paste)

Blender 4.5 LTS (supported to July 2027): **Cycles** = path-traced photoreal; **EEVEE Next** = fast
rasterizer (great for motion graphics / previews). Drive it headless for repeatable renders:

```python
# render_logo.py  —  run headless:  blender -b -P render_logo.py
import bpy, math

scene = bpy.context.scene
scene.render.engine = "CYCLES"                  # photoreal; use "BLENDER_EEVEE_NEXT" for fast/MoGraph
scene.cycles.device = "GPU"                     # ensure a GPU is enabled in preferences/CLI
scene.cycles.samples = 256
scene.cycles.use_denoising = True               # OptiX/OIDN denoiser
scene.view_settings.view_transform = "AgX"      # filmic view transform (Blender 4.x default)
scene.render.resolution_x, scene.render.resolution_y = 2160, 2160
scene.render.film_transparent = True            # alpha for compositing the logo

# --- clean slate
bpy.ops.object.select_all(action="SELECT"); bpy.ops.object.delete()

# --- import the canonical logo SVG and extrude it (vector stays the source of truth)
bpy.ops.import_curve.svg(filepath="//logo.svg")
curve = [o for o in bpy.context.scene.objects if o.type == "CURVE"][0]
curve.data.extrude = 0.06                        # depth
curve.data.bevel_depth = 0.01                    # soft edge catches light

# --- gold PBR material (metalness workflow)
mat = bpy.data.materials.new("Gold"); mat.use_nodes = True
bsdf = mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.83, 0.66, 0.22, 1.0)
bsdf.inputs["Metallic"].default_value = 1.0
bsdf.inputs["Roughness"].default_value = 0.18
curve.data.materials.append(mat)

# --- HDRI world (image-based lighting) + a key area light (3-point backbone)
world = bpy.data.worlds["World"]; world.use_nodes = True
env = world.node_tree.nodes.new("ShaderNodeTexEnvironment")
env.image = bpy.data.images.load("//studio.hdr")
world.node_tree.links.new(env.outputs["Color"],
                          world.node_tree.nodes["Background"].inputs["Color"])
key = bpy.data.lights.new("Key", "AREA"); key.energy = 800; key.size = 3
key_obj = bpy.data.objects.new("Key", key); bpy.context.collection.objects.link(key_obj)
key_obj.location = (4, -4, 5); key_obj.rotation_euler = (math.radians(55), 0, math.radians(45))

# --- camera with shallow DOF (the "expensive" depth tell)
cam = bpy.data.cameras.new("Cam"); cam.lens = 85; cam.dof.use_dof = True; cam.dof.aperture_fstop = 2.0
cam_obj = bpy.data.objects.new("Cam", cam); bpy.context.collection.objects.link(cam_obj)
cam_obj.location = (0, -8, 1.2); cam_obj.rotation_euler = (math.radians(85), 0, 0)
scene.camera = cam_obj
cam.dof.focus_object = curve

# --- output (multi-frame? set scene.frame_start/end + animate, then use animation render)
scene.render.image_settings.file_format = "OPEN_EXR"   # 32-bit linear for grade/comp
scene.render.image_settings.color_depth = "32"
scene.render.filepath = "//out/logo_"
bpy.ops.render.render(write_still=True)
```

Render **EXR (linear, multi-pass)** for anything going to comp/grade; PNG/JPEG only for final flat
deliverables. For motion graphics, animate via keyframes/F-curves or **Geometry Nodes**, set
`frame_start/end`, render an EXR/PNG **sequence** (never a single mp4 from Blender for a finishing
pipeline) and encode in post.

## Three.js / React Three Fiber — real-time (R3F v9, WebGPU)

R3F **v9.x** (React 19) is the stable production line; Three.js **r171+** ships production-ready
**WebGPU** via `three/webgpu` (TSL shaders, automatic WebGL2 fallback). WebGPU needs **async renderer
init** — R3F supports an async `gl` factory. (v10 is alpha/canary: adds WebGPU first-class + renames
`state.gl`→`state.renderer` — don't ship alpha for clients yet.)

```tsx
// Real-time metallic logo with HDRI lighting + DOF — WebGPU with WebGL2 fallback
import * as THREE from "three/webgpu";
import { Canvas } from "@react-three/fiber";
import { Environment, OrbitControls, Center, MeshTransmissionMaterial } from "@react-three/drei";

function Mark() {
  return (
    <Center>
      <mesh>
        <torusKnotGeometry args={[1, 0.32, 220, 32]} />
        {/* metalness workflow: 1 = metal, low roughness = polished */}
        <meshStandardMaterial color="#d4af37" metalness={1} roughness={0.16} />
      </mesh>
    </Center>
  );
}

export default function Scene() {
  return (
    <Canvas
      shadows
      camera={{ fov: 40, position: [0, 0, 6] }}
      gl={async (props) => {                     // WebGPU requires async init
        const renderer = new THREE.WebGPURenderer(props as any);
        await renderer.init();
        return renderer;                          // falls back to WebGL2 automatically
      }}
    >
      <ambientLight intensity={0.3} />
      <directionalLight position={[4, 5, 3]} intensity={2.4} castShadow />
      <Mark />
      <Environment preset="studio" />            {/* HDRI image-based lighting + reflections */}
      <OrbitControls enablePan={false} />
    </Canvas>
  );
}
```

Glass logo: swap `<meshStandardMaterial>` for drei's `<MeshTransmissionMaterial transmission={1}
roughness={0.05} ior={1.45} thickness={0.5} />`. Post FX (bloom/DOF) via
`@react-three/postprocessing` — note some effects need WebGPU/TSL-compatible versions in 2026.

## Spline (designer-fast hybrid)

Use **Spline** for quick web 3D / interactive scenes when a designer owns the asset and dev control is
secondary — author in-app, then **export to React/Three.js** (or embed) or to a glTF/PNG. Good for
landing-page 3D and product spins; for full control or heavy perf budgets, drop to raw R3F.

## Motion graphics

- **Web/app**: prefer **Lottie** (vector, tiny) for 2D UI motion; **R3F** for 3D. Animate by frame,
  ease with springs/curves; respect `prefers-reduced-motion`.
- **Video**: Blender (keyframes/Geometry Nodes) for 3D MoGraph rendered to a sequence, or **Remotion
  `@remotion/three`** when the 3D must composite with exact text/brand overlays — drive with
  `useCurrentFrame()`, not `useFrame()` (see `cinematic-5d-video-production` / `remotion-programmatic-video`).
- **Principles**: timing/spacing, anticipation, follow-through, ease in/out. Random spin ≠ motion design.

## Edge cases / gotchas

- **Color-space mixups**: normal/roughness/metal maps must be **linear (non-color)**; albedo is sRGB.
  Wrong = washed/plastic materials.
- **Metalness in-between** (0.3, 0.6) → almost always wrong; keep 0 or 1, use roughness for variation.
- **Fireflies** in Cycles (bright speckles) → clamp indirect, more samples, denoise, or larger lights.
- **WebGPU not everywhere**: ship with WebGL2 fallback (the async factory does this); test Safari.
- **R3F `useFrame` in Remotion**: forbidden (non-deterministic) — use `useCurrentFrame`.
- **glTF scale/orientation**: exporters differ; verify units (meters) and Y-up vs Z-up on import.
- **Single mp4 from Blender**: don't — render a frame sequence, encode in post for control.

## Performance / render-cost

- **Real-time (R3F)**: budget polys + draw calls; use **instancing** for repeats, **LOD**, compressed
  textures (KTX2/Basis), **Draco/meshopt** glTF compression, frustum culling, and bake lighting where
  static. Target 60fps on the *worst* device you support. Dispose geometries/materials on unmount.
- **Offline (Blender)**: EEVEE Next for previews/MoGraph (seconds), Cycles for hero (minutes); GPU +
  **denoiser** to cut samples; render farm / cloud for sequences; render **proxies** for editorial,
  full-res after lock. Adaptive sampling + light clamping save hours.
- Track render-hours and **$ per delivered frame** for cloud/farm jobs.

## Rights / licensing & brand safety

- **HDRIs / textures / models**: verify license (PolyHaven CC0 is safe; marketplace assets vary — check
  commercial + redistribution terms). Don't ship someone's paid model in client deliverables without a
  license.
- **Fonts in 3D**: same as logo — license for the use, prefer importing **outlined** vector.
- **Software licensing**: Blender is GPL/free (incl. commercial). Confirm any add-on/render-farm terms.
- **AI-generated 3D / textures**: check provenance + commercial rights; redraw/rebuild for ownership.

## Consistency / scale

- **One source asset → many outputs**: keep the canonical 3D file/scene; script variants (color,
  angle, format) headlessly (the bpy pattern above) rather than re-doing by hand.
- **Material/light library**: reusable PBR materials + HDRI set + camera rig presets per brand.
- **Pull brand color** from `color-design-master` tokens; build the 3D logo from `logo-5d-pro`'s
  canonical SVG so it can never drift from the flat mark.

## QA / review

```
- [ ] Runtime chosen correctly (web→R3F / shot→Blender) before authoring
- [ ] Linear color pipeline; color vs data maps in correct space; view transform applied at end
- [ ] Metalness 0/1 (not in-between); roughness sells the surface; glass IOR sane
- [ ] 3-point/HDRI lighting with intentional ratio + color temp
- [ ] Real-time: 60fps on target device; instancing/LOD/compressed textures; disposes on unmount
- [ ] Offline: EXR multi-pass for comp/grade; denoised; proxies for editorial
- [ ] Asset licenses (HDRI/textures/models/fonts) cleared
```

## Delivery specs (formats / color)

| Use | Format | Notes |
|-----|--------|-------|
| **Web 3D** | **glTF/GLB** (Draco/meshopt), KTX2 textures | smallest, standard; embed or React/Three |
| **Render to comp/grade** | **OpenEXR** (linear, 16/32-bit), multi-pass | beauty + depth/normals/cryptomatte/motion |
| **Flat still** | PNG (alpha) / TIFF 16-bit | sRGB or Display-P3 (tagged) |
| **MoGraph video** | PNG/EXR **sequence** → ProRes 4444 (alpha) / H.265 | encode in post, not from Blender |
| **Web motion** | **Lottie JSON** (2D) / live WebGL (3D) | tiny, scalable, reduced-motion aware |

## Accessibility & i18n / RTL

- **`prefers-reduced-motion`**: pause/disable auto-spin and heavy animation; provide a static frame.
- **Don't gate content on WebGL**: real-time 3D is decorative-enhancement — provide a static image
  fallback for no-WebGPU/low-power/`save-data` devices; never put essential info only in the canvas.
- **Performance = accessibility**: a 12fps scene on a mid phone is an exclusion; budget for it.
- **i18n/RTL**: any text in a 3D scene should be overlaid (DOM/Remotion) so it can localize/mirror; if
  baked into geometry, build per-locale variants and mirror layout for RTL.
- **Photosensitivity**: avoid >3 flashes/sec and strobing emissives.

## Anti-patterns

- Choosing the runtime last (rebuilding the whole scene when "wait, it needs to be on the web").
- Shipping a path-traced static hero as live WebGL (burns client GPU for no interactivity).
- Metalness sliders at 0.5; mixing sRGB/linear maps; lighting in display gamma.
- Encoding a single mp4 straight out of Blender for a finishing pipeline.
- `useFrame` inside Remotion; alpha R3F v10 in client production.
- Uncompressed glTF + 4K textures tanking the page; never disposing GPU resources.
- Unlicensed HDRIs/models/fonts in client deliverables.

## Agent checklist

```
- [ ] Runtime decided (web/offline) up front; pipeline matches
- [ ] PBR metalness workflow; linear color; correct map color-spaces
- [ ] HDRI + 3-point lighting with ratio/temp intent; DOF for depth
- [ ] Real-time: WebGPU + WebGL2 fallback, 60fps, instancing/LOD/compression, disposal
- [ ] Offline: headless bpy for reproducibility; EXR multi-pass; denoise; proxies
- [ ] Built from canonical SVG/brand tokens; asset licenses cleared
- [ ] reduced-motion + static fallback; RTL/i18n text overlaid not baked
```

## References (2026-current)

- Blender 4.5 LTS: https://www.blender.org/download/releases/4-5/ · bpy API: https://docs.blender.org/api/current/
- Three.js: https://threejs.org/docs/ · WebGPU/TSL: https://threejs.org/docs/#manual/en/introduction/How-to-use-WebGPURenderer
- React Three Fiber: https://r3f.docs.pmnd.rs/ · drei: https://github.com/pmndrs/drei
- Spline: https://spline.design/ · Poly Haven (CC0 HDRIs): https://polyhaven.com/
- glTF + Draco/KTX2: https://www.khronos.org/gltf/ · Lottie: https://lottiefiles.com/

## Related

`logo-5d-pro` (canonical vector to dimensionalize), `image-5d-pro`, `cinematic-5d-video-production`,
`color-grading-cinematic` (this master); `remotion-programmatic-video` (video-ai-master);
`color-design-master`, `ui-master`.
