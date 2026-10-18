# Tesla APK Asset Studio

Native SwiftUI + Metal ray tracing viewer for the 12 vehicle scenes extracted from Tesla Android 4.61.6. Run `../launch_metal_viewer.sh` from this directory, or open `TeslaMetalViewer.app`. The launch script rebuilds the executable and refreshes bundled models.

Before investigating a car artifact, read [the APK source guide](../SOURCES.md) for the stable decoded-resource location, original scene/material/animation files, and how to regenerate missing extracts. Full Java/Kotlin decompilation is usually unnecessary for vehicle rendering issues.

## What changed

- Materials follow each source surface's resource path and instance override. Window, chrome, paint, rubber, and interior assignments no longer depend on mesh-name guesses or hardcoded triangle regions.
- Albedo, packed metallic/roughness/AO maps, UV2 AO, and paint custom-color masks are retained. Android ETC textures are sampled directly by Metal; lossless source textures remain embedded in the GLBs.
- Decimal JSON transforms are explicitly converted through NSNumber. Wheel mounts, light lenses, pivots, and animation keyframes keep their source transforms.
- The inspector exposes 161 usable source clips as checkboxes with shared playback and scrubbing. Compatible clips play together; shorter clips hold their end pose, and selecting a clip that controls the same joint channel replaces its conflicting selection. All keyframes are retained, including compound falcon-wing tracks. Absent regional variants and sensor-only tracks are recorded in `../models/source-audit.json`.
- Driving ports the APK road texture, lane placement, UV scrolling, and wheel-socket rotation. Climate ports the source airflow planes, edge-fade shader, timing and colors; its seamless noise is generated using Godot's OpenSimplex algorithm and the APK's parameters. Charging uses the APK cable meshes, source charge-port anchor, and flow shader.
- Cybertruck wheels attach to the animated source Spatials, including the rear axle; the suspension raises the body while keeping all four tires grounded. Windows use neutral optical transmission with optional privacy tint, independent of Godot blend colors.
- Light covers use neutral 100% optical transmission and adjustable reflection (15% of the ordinary glass Fresnel response by default) and traverse nested lens shells, so the source light assemblies remain visible. Rubber uses a matte, nonmetallic finish with a subdued reflection lobe. These are viewer material calibrations; APK resource bindings remain intact.
- Area-light sampling produces soft ray-traced shadows; ground occlusion supplies tire contact shadows. Progressive rendering resumes after camera movement stops.

## Lighting and material repair

The source texture pipeline, Semi inline paint override, and Palladium tire textures are restored. Lamp controls use separate emission colors and source emission atlases, preserving body paint and black trim. Rear running lamps and original indicator paths are exported for S/X, and E41 split DRLs/high beams are retained. See the [Git/source review](../evidence/lighting-material-review.md) and its front/rear review sheets.

`--validate-lights` checks all vehicles in five lamp states and verifies that their surface materials remain unchanged. Offscreen exports support `--lights-off`, `--brake-lights`, `--signal-left`, `--signal-right`, and optional `--light-beams`. `--dump-lights` prints source emitter locations for diagnosis. Headlight beams use source lamp positions independently of paint choice.

## Controls

Two-finger motion or left/middle drag orbits. Hold Shift to pan; right drag also pans. Pinch, mouse wheel, or Control + two fingers zooms. Gestures keep their initial mode until release, ignore trackpad momentum, and scale pan speed to distance and viewport size. Next Model in the header cycles through vehicles and wraps at the end. During a tour it preserves the tour clock and stage, adapting the camera to the next vehicle. Fit and the five camera presets frame the vehicle. The Tour button and Camera tour inspector restore the cinematic walkthrough, with speed, progress, and restart controls. Manual navigation stops camera automation. A persistent inspector contains model, paint, source-animation, runtime-effect and floor controls, plus a component/material audit. Airflow uses the source planes and noise, with ray-traced visibility: opaque panels block it, glass transmits it, and a panel behind glass still blocks it. Charging opens the source charge-port clip and shows the US cable when that anchor exists.

Finish contains **Window surrounds: Original / Chrome / Chrome delete** and a **Headlight reflection** slider. Original preserves source materials. The other finishes affect only exported window-surround triangles, isolated using source exterior/trim bindings and proximity to side-pane boundaries and the outer silhouette. This is a geometric viewer customization, rather than an APK component label; internal pillars, glass, lamps and interior chrome retain their materials. `models/source-audit.json` records selected triangle counts per source surface.

Scene & atmosphere contains **Studio / Overcast / Golden hour / Blue hour / Neon rain / Coastal storm**. Presets change the sky, key light, ambient fill, floor and shadows together.

- **Neon rain** adds an original 3D street set: buildings, illuminated windows, cyan/red neon storefronts, raised pavement and bollards. These meshes share the vehicle acceleration structure and appear in ray-traced reflections and shadows.
- **Coastal storm** adds a misty coastal horizon, cloud variation and 3D roadside guardrails.
- Both weather scenes have independent **Rain** and **Surface wetness** controls. World-space road grain, worn lane markings, irregular puddles, animated ripple normals and distance haze replace the studio floor. Rain streak intersections stop at the first visible surface. Paint gains subtle bead-normal detail and a water coat. Set rain to zero for an after-rain look; set both sliders to zero for a dry road.
- **Animate weather** can be paused for progressive accumulation and clean screenshots, independently of source vehicle, driving and climate animations. Weather controls have no effect on the four original studio/daylight scenes.
- Paint uses an energy-conserving GGX base and a separate dielectric clearcoat lobe. Direct area-light highlights are stabilized while shadow rays still sample the light area. Secondary road/body/glass reflections now shade the actual intersected material with texture color and lighting instead of using a flat base color.

These are original procedural viewer scenes inspired by cinematic automotive photography, not APK backgrounds or a full path tracer. They move the viewer toward a racing-game presentation; they do not supply a full AAA game world, licensed game assets, volumetric clouds, or a multi-bounce light transport engine.

## Rebuild and verify

Requires macOS 14+, an Apple Silicon Metal ray-tracing device, Xcode's Swift toolchain, REA, and Python with NumPy/Pillow. Nothing is installed automatically.

```sh
python3 ../tools/rebuild_assets.py /absolute/path/to/tesla.apkm
./create_app_bundle.sh
.build/release/TeslaMetalViewer --validate-models
```

The asset rebuild starts from the APKM and extracts the nested asset-pack APK with REA. No temporary extraction path is hardcoded. Extraction provenance is saved in `../evidence/rea-extraction.json`.

Offscreen exports use the same Metal shaders as the app:

```sh
.build/release/TeslaMetalViewer --model modelx_plaid --animation LRDoorAnimationComplete --animation-time 1 --render-out /tmp/modelx-open.png
.build/release/TeslaMetalViewer --model model3_high --preset rear --charging --animation ChargeportAnimation --animation-time 1.5 --render-out /tmp/charging.png
.build/release/TeslaMetalViewer --model model3_high --climate 1 --driving 30 --effect-time 2 --render-out /tmp/effects.png
```

Use `--lighting golden-hour --trim chrome --paint pearl_white --exposure 1.2` for a lighting export; `--trim chrome-delete` selects black surrounds. `--lens-reflection 0` removes the outer light-cover reflection for inspection.

Weather exports use the same controls as the app, with a frozen weather clock for repeatable accumulation:

```sh
.build/release/TeslaMetalViewer --model model3_high --lighting neon-rain --paint ultra_red --rain 0.65 --wetness 0.85 --effect-time 2 --samples 256 --render-out /tmp/neon-rain.png
.build/release/TeslaMetalViewer --model model3_high --lighting coastal-storm --paint quicksilver --render-out /tmp/coastal-storm.png
python3 ../tools/render_weather_smoke.py
```

Exports default to 128 samples; `--samples 1...1024` trades render time for cleaner reflections. `render_weather_smoke.py` renders on the real Metal device and checks nonblank output, weather isolation in the studio, dry-scene stability, animated weather differences and distinct scene presets. It requires Pillow.

Pass comma-separated clip names to `--animation` to render simultaneous clips, for example `--animation HoodAnimation,RFDoorAnimation`. In the app, check multiple clips, then Play or scrub their shared timeline. Play restarts from zero after reaching the end.

`--validate-features` checks optical window/lens materials, matte rubber, all four Cybertruck tires at all six suspension keyframes, combined poses, conflicting selection, playback restart, tour motion, navigation routing, pan scaling, and tour-preserving model cycling. It also executes the actual Metal airflow visibility function against opaque, glass, glass-plus-body, unobstructed, and beyond-plane geometry fixtures.

`--climate 1` selects cool, `2` selects heat. `--driving` is signed mph. Unknown animation names fail explicitly. `--validate-models` loads every vehicle and verifies that every exported clip moves visible vertices.

## Fidelity boundaries

This is a Metal translation of Godot assets and selected runtime shaders, not Tesla's Godot renderer. It retains source material bindings, scalar PBR values, texture maps, geometry, pivots and supported transform/value tracks. Normal maps, arbitrary Godot shaders, FSD/rainbow/terrain logic, regional charging connectors and every configuration variant are not implemented. The studio lighting and tone mapping are viewer features. Source codenames are shown without assigning speculative trim specifications.

The legacy browser viewer shares the corrected material metadata and keyframe data; the complete runtime-effect implementation and native inspector are in this Metal app.

## Bayberry optics and blinking indicators

Bayberry and E80 retain the authored downward-facing parking emitter. A finite red light wash illuminates the recessed TESLA panel beneath the upper lip, with a narrow vertical falloff that keeps the body below dark. This is an analytic area-light approximation; the parking strip is not replaced by an outward-facing ribbon. Bayberry and E80 rear turn emitters are red. Source variants without dedicated rear indicator geometry use their left/right red brake fixtures, preserving source placement and materials. E41’s coplanar emitter is separated from its optical cover by 2 mm to avoid transmission-ray self-intersection.

Indicators blink at 80 cycles/minute with a 50% duty cycle, start immediately when selected, and share a synchronized clock when both sides are enabled. Brake-only operation stays steady on shared brake/indicator fixtures. Progressive accumulation resets at phase changes to avoid ghosting.

Interior lightbars are disabled on every model. Generated bars, source interior LED strips, RGB ambient spill, and interior lighting controls have been removed. Exterior lighting is independent.

```sh
.build/release/TeslaMetalViewer --model bayberry --preset rear --signal-left --effect-time 0.1 --render-out /tmp/indicator-on.png
.build/release/TeslaMetalViewer --model bayberry --preset rear --signal-left --effect-time 0.5 --render-out /tmp/indicator-off.png
python3 ../tools/render_lamp_effects.py
```

`tools/render_lamp_effects.py` renders both rear blink phases independently on both sides of all 12 vehicles from directly behind. It checks visible fixture changes on the selected side, rejects opposite-side blinking, and separately checks indirect Bayberry panel lighting, steady brakes. `--rear-straight` selects this diagnostic camera during offscreen export.

Rear circuit corrections: E41 exports the hidden authored `Brake_Light` mesh for its outer running circuits and adds a narrow center diffuser fitted to the authored rear panel, because this source trim omits the center emitter. Cybertruck corner lamps split at the continuous running bar’s lower edge: upper running sections stay steady during signaling and turn off together with the upper bar during braking; lower sections carry turn/brake emission. Dark-phase signal overlays transmit rays so Model S’s steady running outline is not covered by a black signal mesh.
