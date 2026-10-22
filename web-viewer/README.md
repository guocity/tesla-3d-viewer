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

**Day / Night** in the Tesla bottom bar uses the original Garage state machine’s authored N shortcut, preserving its sky, lighting, reflections, camera and HUD. The mini-player is hidden by setting only its Visor container opacity in the assembled runtime buffer; the source `.riv` stays unchanged. No replacement scene is used. The BMW Panel and Visor UI roots are hidden in the assembled buffer. Tesla top and bottom bars sit above the original scene; vehicle controls and display settings start closed. Each appearance command explicitly focuses the Garage keyboard target before sending N, advances between key-down and key-up, and releases focus afterwards. The HTML label changes only when Rive accepts the command, including after a model reload.

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

## Charging control

The menus use translucent glass surfaces. The legacy steering, headlight and fan hotspots are collapsed to disable their hit targets. An accessible plug control follows the scene’s projected charging point. Clicking it plays the source charge-port clip, then connects the model’s APK charger handle and cable where those assets are available. Clicking again removes the charger before closing the port. The charger starts hidden, and changing models resets the connection. The plug and cable stay in their fitted pose and fade using tagged-vertex coverage in the original scene shader. The plug-shaped charging indicator fades in/out and gently changes opacity while connected. Cybertruck and the Juniper variants have no packaged cable geometry, so they show the charging indicator and available port animation without a cable.

Vehicle picker thumbnails use locally bundled studio/stock images; source URLs and generation mappings are recorded in `src/assets/vehicles/SOURCES.md`. Juniper E41/E80 share the verified Juniper exterior image.

Cybertruck charging retains the source scalar Bezier rotation channels and their time/value handles. Its `Spatials/ChargeportMarker` supplies the charging cable anchor when the older `ChargePort` node is absent.

For the live viewer regression check, start `npm run dev`, open its URL with `playwright-cli -s=viewer-check open <url>`, then run `playwright-cli -s=viewer-check run-code "$(cat scripts/check-viewer.browser.js)"`. This checks scene-authored day/night commands across HTML focus changes and vehicle reloads, Cybertruck charging/disconnect, default-off roof bar, and all twelve studio images. Run `python3 tools/test_charging_export.py` from the repository root for the exporter regression.

Drags beginning on the charging plug are forwarded to the showroom camera for both mouse and touch; a tap still operates the charger. Cybertruck rear lighting has three red running segments (center plus the upper left/right fixtures), exclusive of the separate lower brake sections. Front square covers are clear with round internal projectors; turn emitters default off.

`ads/lgnat.jpg` supplies the monitor's first ad (black LGNAT.COM on white). The existing LED monitor alternates the ad with its original color program, retaining perspective, occlusion, reflections and lighting.

On phones, the bottom bar uses one row with Controls, Display and Day/Night;
climate readouts and climate icons are hidden. Menus stay within the viewport,
interactive targets are at least 44px, and safe-area insets protect controls from
notches and home indicators. Landscape uses compact scrollable panels. The
charging hotspot is kept between the actual header and bottom bar.

Run `playwright-cli -s=viewer-check run-code "$(cat scripts/check-mobile.browser.js)"`
against the viewer for six phone/tablet layouts, native emulated touch taps,
vehicle-menu scrolling, search, vehicle toggles, charger dragging, direct canvas
rotation, charging/disconnect and day/night. This is Chromium mobile emulation;
physical iOS/Android browser checks are separate.

Road wheel covers on all vehicles use the matte `BottomCar` preset. Overrides
match road wheel nodes and their rim materials; body and steering-wheel materials
retain their original mapping.

## Charging and orbit controls

Charging opens the source port and fades in the APK cable. A smooth green pulse travels from the cable end toward the handle using the original UV direction and 1.5-second timing. Charging moves to a low front-biased charge-port-side view in 260 ms, releases the camera for free orbit, then opens only the charge port and connects the cable. Camera geometry, reflection projection and every PBR material eye position move together, preserving the body finish. The connected charge button docks away from the port without a tooltip. Mouse/touch input interrupts the transition and remains available afterwards. Bayberry, E41 and E80 retain the source cable at their `ChargePortMarker` anchors. Vehicle fitting excludes the loose cable, which rests on the floor without moving the connected end.
