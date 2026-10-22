# Tesla APK Asset Studio

Start the native Metal viewer with `./launch_metal_viewer.sh`. See [the native viewer documentation](TeslaMetalViewer/README.md) for source animation playback, driving/climate/charging effects, controls, asset reconstruction and validation.

[Source material and animation audit](models/source-audit.json) · [REA extraction provenance](evidence/rea-extraction.json)

The native viewer now includes layered GGX car paint, shaded ray-traced reflections, and **Neon rain** / **Coastal storm** scenes with wet roads, animated rain and 3D set dressing. Select them under **Scene & atmosphere**. See [neon rain](previews/neon-rain.png) and [coastal storm](previews/coastal-storm.png) previews. Pause **Animate weather** for cleaner stills.

The browser viewer is isolated in [`web-viewer/`](web-viewer/README.md) and uses pnpm. Run `cd web-viewer && pnpm install && pnpm dev`. Its default view uses the reference Rive vehicle interface and its original scene/player; the earlier Three.js APK asset studio remains available at `/legacy/`. The native macOS app is independent of the web package.

For future artifact fixes, start with [APK source locations and troubleshooting](SOURCES.md). It identifies the preserved complete Godot extract, original APKM, component/material audit, decoding limits, and rebuild steps.

The web viewer supports compressed, cached loading and APK animation playback. See [GitHub Pages deployment instructions](web-viewer/README.md#github-pages) for the prepared static assets and manual deployment workflow.
