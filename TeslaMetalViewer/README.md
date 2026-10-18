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

## Controls

Two-finger motion or left/middle drag orbits. Hold Shift to pan; right drag also pans. Pinch, mouse wheel, or Control + two fingers zooms. Gestures keep their initial mode until release, ignore trackpad momentum, and scale pan speed to distance and viewport size. Next Model in the header cycles through vehicles and wraps at the end. During a tour it preserves the tour clock and stage, adapting the camera to the next vehicle. Fit and the five camera presets frame the vehicle. The Tour button and Camera tour inspector restore the cinematic walkthrough, with speed, progress, and restart controls. Manual navigation stops camera automation. A persistent inspector contains model, paint, source-animation, runtime-effect and floor controls, plus a component/material audit. Airflow uses the source planes and noise, with ray-traced visibility: opaque panels block it, glass transmits it, and a panel behind glass still blocks it. Charging opens the source charge-port clip and shows the US cable when that anchor exists.

Finish contains **Window surrounds: Original / Chrome / Chrome delete** and a **Headlight reflection** slider. Original preserves source materials. The other finishes affect only exported window-surround triangles, isolated using source exterior/trim bindings and proximity to side-pane boundaries and the outer silhouette. This is a geometric viewer customization, rather than an APK component label; internal pillars, glass, lamps and interior chrome retain their materials. `models/source-audit.json` records selected triangle counts per source surface.

Studio contains **Studio / Overcast / Golden hour / Blue hour** lighting and exposure. Presets change sky reflections, key-light position and color, ambient fill, floor illumination, and shadows together. The surface shader uses GGX direct specular and Fresnel environment reflection. The environments are procedural viewer lighting, not APK backgrounds or a full path tracer.

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

Pass comma-separated clip names to `--animation` to render simultaneous clips, for example `--animation HoodAnimation,RFDoorAnimation`. In the app, check multiple clips, then Play or scrub their shared timeline. Play restarts from zero after reaching the end.

`--validate-features` checks optical window/lens materials, matte rubber, all four Cybertruck tires at all six suspension keyframes, combined poses, conflicting selection, playback restart, tour motion, navigation routing, pan scaling, and tour-preserving model cycling. It also executes the actual Metal airflow visibility function against opaque, glass, glass-plus-body, unobstructed, and beyond-plane geometry fixtures.

`--climate 1` selects cool, `2` selects heat. `--driving` is signed mph. Unknown animation names fail explicitly. `--validate-models` loads every vehicle and verifies that every exported clip moves visible vertices.

## Fidelity boundaries

This is a Metal translation of Godot assets and selected runtime shaders, not Tesla's Godot renderer. It retains source material bindings, scalar PBR values, texture maps, geometry, pivots and supported transform/value tracks. Normal maps, arbitrary Godot shaders, FSD/rainbow/terrain logic, regional charging connectors and every configuration variant are not implemented. The studio lighting and tone mapping are viewer features. Source codenames are shown without assigning speculative trim specifications.

The legacy browser viewer shares the corrected material metadata and keyframe data; the complete runtime-effect implementation and native inspector are in this Metal app.
