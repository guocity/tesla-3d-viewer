# APK source assets for investigating car artifacts

Start here when fixing a vehicle's geometry, component materials, textures, pivots, or animations. The extracted Godot resources are the reference for what Tesla shipped. The viewer GLBs are generated translations and can contain conversion errors.

Full Android Java/Kotlin decompilation is usually unnecessary for these issues. Rendering, lighting, camera controls, tour state, and the Metal port's occlusion can often be fixed in the viewer alone. Consult the original resources when an issue depends on which surface, transform, texture, or animation track the APK actually uses.

## Source locations

Paths below are relative to this repository (`tesla-3d-viewer/`).

| Location | Contents and purpose |
| --- | --- |
| `../analysis/com.teslamotors.tesla/4.61.6/raw/godot/` | **Complete preserved Godot asset extract. Start here.** Contains `Ego/`, `mobile/`, `animations/`, `Energy/`, and the hidden `.import/` directory with compiled resources. |
| `../extracted_models/Ego/` | Earlier organized extract with vehicle `.tscn` scenes, material resources, and import descriptors. Convenient for reading scene hierarchies and source animation keys. |
| `../extracted_models/models_by_vehicle/Ego/` | Earlier organized compiled `.scn` / `.mesh` resources used by the converter's local export workflow. |
| `../apk/com.teslamotors.tesla_4.61.6-4647-4647_1arch_7dpi_24lang_1feat_15e99b04241942c48c066c4afe62f5d9_apkmirror.com.apkm` | Original supplied APKM. The Godot assets are inside its **`split_assets_pack.apk`**, under `assets/godot/`. Inspecting only the base APK misses them. |
| `models/*.glb`, `models/catalog.json` | Generated viewer assets and vehicle index; not the original APK resource files. |
| `models/source-audit.json` | Component paths, per-surface source material bindings, window-trim triangle counts, retained clips, and omitted-track reasons. Use it to trace a visible artifact back to a resource. |
| `evidence/rea-extraction.json` | REA extraction provenance and hashes of the APKM and nested asset-pack APK. |
| `evidence/source-locations.json` | Machine-readable source locations and preservation verification. |

On this computer, the stable, complete extract is:

```text
/Users/m4air/Documents/github/android_apk/analysis/com.teslamotors.tesla/4.61.6/raw/godot/
```

It was preserved on 2026-10-18 from the existing REA extraction. All 4,397 copied files (456,127,688 bytes) were compared with their originals using SHA-256. This avoids depending on the earlier `/var/folders/.../T/rea-extracted-*` directories, which are temporary and may disappear.

The APKM, organized extracts, and `analysis/.../raw/` files are **local, Git-ignored inputs**. A clone of this viewer repository does not include them. If missing, restore the supplied APKM and extract it with REA as described below; do not assume an old temporary directory still exists.

## What to inspect for each issue

| Artifact | Original resources | Viewer implementation |
| --- | --- | --- |
| Wrong part, wheel mount, pivot, or suspension | Vehicle `Ego/<variant>/*.tscn`, imported `.scn` / `.mesh`, and all animation tracks targeting that component | `tools/convert_assets.py`, `tools/validate_assets.py`, `TeslaMetalViewer/Sources/GLBLoader.swift` |
| Wrong glass, chrome, rubber, or paint assignment | Actual surface material overrides; `.material` / `.tres` properties; referenced texture import maps and packed metallic/roughness/AO maps | Converter material bindings, `GLBLoader.swift`, `ShaderSource.swift` |
| Window chrome / chrome-delete boundary | Side-window geometry and adjacent exterior surfaces; audit triangle counts | `tools/window_trim.py`. This is a geometric customization mask, **not an APK-provided semantic component label**. Check Original finish when diagnosing it. |
| Door or other source clip moves incorrectly | The complete source clip, its AnimationPlayer root, target path, key times/values, and parent transforms | Converter animation export, validator node binding, loader interpolation and local/world composition |
| Climate passes through panels or has incorrect placement | Vehicle `Airflow_*` transforms, `mobile/materials/airflow_shader.tres`, `mobile/scripts/Airflow.gdc` | `tools/source_effects.py`, loader climate transforms, shader airflow visibility |
| Driving or charging differs from the APK | `mobile/scripts/Road.gdc`, `VehicleManager.gdc`, charging-cable scene/materials and the vehicle's charge-port anchor | `tools/source_effects.py`, `MetalView.swift`, `ShaderSource.swift` |
| Lighting, reflections, camera, or tour issue | Usually no additional APK decode needed; these include viewer-specific behavior | `AppState.swift`, `Camera.swift`, `ContentView.swift`, `MetalView.swift`, `RayTracer.swift`, `ShaderSource.swift` |

For example, the complete source contains `Ego/Cybertruck/Cybertruck.tscn` and `Ego/3_High/Model3_High.tscn`. Godot `res://Ego/...` paths resolve relative to the preserved `godot/` directory, not relative to the viewer repository.

Some resources remain in Godot's compiled/compressed formats. “Extracted” does not mean everything has been decompiled into plain text. `tools/convert_assets.py` reads RSRC/RSCC resources and import mappings; use its parsers rather than treating binary `.material`, `.scn`, or `.mesh` files as text. Source PNG filenames may resolve to compiled textures through `.import` descriptors, so retain the hidden `.import/` directory. `tools/inspect_gdc.py` inspects Godot bytecode tokens without executing the APK; its output is not recovered full GDScript source. Existing token evidence is in `evidence/*-tokens.json`.

## Export from the preserved local sources

From the viewer repository root, with the organized extract still present:

```sh
TESLA_GODOT_ROOT="../analysis/com.teslamotors.tesla/4.61.6/raw/godot" \
  python3 tools/convert_assets.py
python3 tools/validate_assets.py
```

The converter defaults `TESLA_EXTRACTED_ROOT` to the sibling `../extracted_models/` directory. It uses `TESLA_GODOT_ROOT` to find additional original imported resources and textures. These commands overwrite generated GLBs and the catalog. Fix the exporter or source-binding logic before rebuilding; a manual GLB-only repair will be lost on the next export.

## Rebuild if the local extracts are missing

The complete rebuild does not require the older organized extract. It extracts the APKM and nested asset pack through REA, assembles temporary import links, and rebuilds the viewer assets:

```sh
python3 tools/rebuild_assets.py \
  "../apk/com.teslamotors.tesla_4.61.6-4647-4647_1arch_7dpi_24lang_1feat_15e99b04241942c48c066c4afe62f5d9_apkmirror.com.apkm"
```

This rebuild currently does **not** preserve its raw Godot extract at the stable path above. To restore that directory for investigation, use `rea extract-artifact <APKM> --format json`, read `normalized_result.output_root`, then extract `<output_root>/split_assets_pack.apk` the same way. Copy the second result's entire `assets/godot/` directory, including hidden files, into `../analysis/com.teslamotors.tesla/4.61.6/raw/godot/`. Keep the REA evidence and verify the input archive hashes against `evidence/rea-extraction.json`.

REA, Python with NumPy/Pillow, and the native build prerequisites must already be installed; the helpers do not install them.

## Verify and refresh the app

After asset or renderer changes:

```sh
./TeslaMetalViewer/create_app_bundle.sh
./TeslaMetalViewer/.build/release/TeslaMetalViewer --validate-models
./TeslaMetalViewer/.build/release/TeslaMetalViewer --validate-features
python3 tools/render_smoke.py --output /tmp/tesla-renders
```

Inspect rendered results as well as validation output. The app reads its own bundled copy of the GLBs under `TeslaMetalViewer/TeslaMetalViewer.app/Contents/Resources/models/`; changing `models/` alone does not refresh an already-built app bundle. See [the native viewer README](TeslaMetalViewer/README.md) for targeted offscreen renders, simultaneous clips, lighting options, and fidelity limits.
