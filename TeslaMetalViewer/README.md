# Tesla Metal Ray Tracing Studio

A native macOS 3D application written in **Swift + MetalKit** utilizing **Apple Metal hardware-accelerated ray tracing** (`metal::raytracing`) on Apple Silicon (M4).

---

## Key Features

1. **All 12 Extracted Tesla Car Models**:
   - **Cybertruck Cyberbeast** (Tri-Motor AWD, Stainless Steel)
   - **Model 3 Highland** (Redesigned Aero Body)
   - **Model Y Highland / Juniper** (Compact SUV AWD)
   - **Model S Plaid** (Tri-Motor Palladium, Carbon Rotors)
   - **Model X Plaid** (Tri-Motor Falcon Wing SUV)
   - **Tesla Semi** (Class 8 Heavy Duty)
   - **Project Bayberry (Juniper)** (Pre-Production Prototype)
   - **Project Bayberry E41** (High-Downforce Package)
   - **Project Bayberry E80** (Extended Wheelbase Performance)
   - **Project Poppyseed** (Experimental Compact Platform)
   - **Model S (Raven)** (Legacy Performance)
   - **Model X (Raven)** (Legacy Performance)

2. **Apple Silicon Hardware Ray Tracing (`metal::raytracing`)**:
   - Hardware-built BVH acceleration structures (`MTLPrimitiveAccelerationStructure`)
   - Primary camera ray casting with sub-pixel jittered anti-aliasing
   - Ray-traced shadow rays towards studio key lights
   - Secondary ray bounces for realistic metallic body reflections and chrome highlights
   - Progressive temporal accumulation (converges up to 256 samples)
   - ACES film tone mapping & sRGB gamma output

3. **Nice Studio Ground with Real Car Reflections**:
   - Physical ground pedestal positioned at \(y = 0.0\) touching tires
   - Ray-traced ground reflection rays shooting upwards into vehicle undercarriage and wheels
   - Adjustable Ground Reflectivity (\(0.0\) to \(1.0\)) and Ground Roughness (\(0.0\) to \(0.45\))
   - Ground presets: *Mirror Obsidian*, *Studio Satin*, *Matte Pedestal*
   - Contact ambient occlusion and soft vehicle ground shadows

4. **Metallic Paint & Finish Controls**:
   - 8 OEM Tesla paint presets (*Stainless Steel*, *Quicksilver*, *Ultra Red*, *Stealth Grey*, *Deep Blue*, *Pearl White*, *Solid Black*, *Founders Gold*)
   - Metallic Flake slider
   - Paint Roughness slider
   - Clearcoat Gloss slider

5. **Camera Presets & Turntable Orbit**:
   - Camera views: **Hero 3/4**, **Side Profile**, **Front Fascia**, **Rear 3/4**, **Top Aero**
   - Interactive orbit (left-drag), pan (right-drag), and zoom (scroll wheel / pinch)
   - Auto-rotating cinematic **Turntable** orbit mode

---

## How to Launch

### Option 1: One-Click Launch Script
From the repository root:
```bash
./launch_metal_viewer.sh
```

Or from inside `TeslaMetalViewer/`:
```bash
./run.sh
```

### Option 2: Finder
Double-click `TeslaMetalViewer.app` located at:
`tesla-3d-viewer/TeslaMetalViewer/TeslaMetalViewer.app`

### Option 3: Swift CLI
```bash
cd TeslaMetalViewer
swift run
```
