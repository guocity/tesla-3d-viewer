# Web viewer

```sh
cd web-viewer
pnpm install
pnpm dev
```

`pnpm build` prepares assets and builds `dist/`. `pnpm preview` serves it locally. `pnpm build:pages` builds directly from committed prepared assets, as CI does. `pnpm test` checks source animation sampling and scene binary replacement.

## Loading and rendering

The showroom retains the reference Rive scene, lighting, floor, reflections and WebGL2 renderer. Its BMW mesh is split from the shared scene at build time. The shared scene downloads as a 3.0 MB compressed file; the default Model 3 vehicle adds about 1.9 MB. BMW's heavier mesh downloads only when selected. The 40 MB source Rive and raw GLBs are not shipped in `dist/`.

Vehicle conversion happens during asset preparation rather than in the browser. Switching vehicles keeps the page open. Content-addressed compressed assets are cached using Cache Storage when available. Only the shared scene and two decompressed vehicle buffers are retained in application memory. Smooth quality caps drawing resolution at 1.25×; High allows up to 2×. The showroom pauses when the page is hidden.

Compressed `.bin` containers are decoded with the browser's DecompressionStream, so they work on ordinary static hosting without server compression configuration. A current browser with WebGL2, WebAssembly and DecompressionStream is required.

## Scene appearance

**Day / Night** in the Tesla bottom bar uses the original Garage state machine’s authored N shortcut, preserving its sky, lighting, reflections, camera and HUD. The mini-player is hidden by setting only its Visor container opacity in the assembled runtime buffer; the source `.riv` stays unchanged. No replacement scene is used. The BMW Panel and Visor UI roots are hidden in the assembled buffer. Tesla top and bottom bars sit above the original scene; vehicle controls and display settings start closed. The appearance command is advanced between key-down and key-up so the Garage script receives it, including after a model reload.

## Showroom animation switches

Choose a Tesla, then open **Animate vehicle**. Each APK clip is an independent switch: on plays forward and holds the open pose; off plays backward from the current pose and returns closed. Several switches can remain enabled together. There is no play button, slider, clip dropdown or separate animation view.

The source key times/values and node hierarchy are prepared into small animation rigs. The pinned WebGL2 adapter identifies the vehicle vertex buffers by exact mesh signatures and updates only those buffers; Rive continues drawing the original scene, vehicle, reflections and dashboard. Source positions and normals update together. Sampling supports Godot YXZ Euler rotations, quaternion transforms and 12-value row-major transforms. Other UI/index/uniform buffers are not modified. BMW has no APK rig, so its controls show an explanatory message.

The renderer explicitly starts the `Garage` artboard/state machine. The canvas remains covered by the loading UI until a real environment frame has rendered, so the startup Rive logo/blank intro never appears. Backend watchdog/interlock diagnostics may still be printed by the Rive runtime; they do not themselves indicate that scene startup failed.

Combined lamp meshes are split by triangle position along each model’s actual world-space long axis. Front emitters retain white materials and rear emitters use red. Charging-port covers and lamp housings are non-emissive; all lamp lens layers, including the trim shells beneath the outer cover, use the scene’s GlassWhite preset (2% tint). The GlassRed preset (35% tint per surface) is excluded from rear lens layers to avoid stacking opaque-looking red sheets. Per-model asset checks verify front/rear colors, charging covers and lens materials.

## Prepared asset layout

- `site-assets/models/`: compressed packed vehicle geometry.
- `site-assets/animations/`: compressed per-vehicle source rigs and the source animation catalog.
- `site-assets/scene/`: the shared compressed Rive environment.
- `site-assets/manifest.json`: content-addressed paths and sizes.

The static build copies these folders under `dist/data/`. Original GLBs and the archived legacy studio are retained locally as development/source material; the hosted viewer does not download or render a separate studio.

## GitHub Pages

1. Commit `web-viewer/` including **`site-assets/`**, the pnpm lockfile, and `.github/workflows/web-viewer-pages.yml`. The `site-assets` files are needed: the original root `models/` folder is intentionally ignored and is not present in a fresh checkout.
2. In the GitHub repository, choose **Settings → Pages → Source → GitHub Actions**.
3. Run **Actions → Deploy web viewer to GitHub Pages → Run workflow**.

The workflow installs with pnpm, runs tests, builds from the prepared assets, and publishes only `web-viewer/dist/`. It is manually triggered; local changes do not deploy automatically. All runtime paths are relative and support project URLs such as `https://OWNER.github.io/REPO/`.

The complete compressed deployment payload is approximately 45 MB plus the runtime and viewer code, below GitHub Pages' 1 GB published-site limit. Each file is below GitHub's normal per-file limit. Visitors only download their selected vehicle; small source animation rigs are loaded with their selected vehicle. No APK, Metal build or extraction tool is required on the hosting server.

After changing locally extracted models or conversion code, run `pnpm prepare:assets` and commit the refreshed `site-assets/`. A clean checkout without `../models/catalog.json` validates and reuses those prepared assets instead of trying to extract/rebuild them.

## Source and ownership

Reference: https://rive-vehicle-interface-i8bka7.uat.rive.to/

`reference-assets.json` records the original URLs and checksums. The checked-in `.riv` is retained as conversion source, unchanged; vehicle payloads and fixed-width captions are replaced only in assembled runtime buffers. The reference scene/player retain their original ownership and terms; this repository grants no additional license for them.

The native `../TeslaMetalViewer`, launcher, shared model sources and extraction tools are independent of this package and unchanged.
