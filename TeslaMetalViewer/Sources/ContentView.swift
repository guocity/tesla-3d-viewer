import SwiftUI

public struct ContentView: View {
    @ObservedObject var state: AppState
    let rayTracer: RayTracer
    
    @State private var isSidebarVisible: Bool = false
    
    public var body: some View {
        ZStack(alignment: .topLeading) {
            // Full-screen Background Metal Ray Tracing Viewport
            MetalViewport(state: state, rayTracer: rayTracer)
                .edgesIgnoringSafeArea(.all)
            
            // Top HUD Bar
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("TESLA")
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .tracking(3)
                                .foregroundColor(.white)
                            
                            Text("METAL RAY TRACER")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.90))
                                .cornerRadius(4)
                                .foregroundColor(.white)
                            
                            Button(action: {
                                switchToNextModel()
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "forward.fill")
                                        .font(.system(size: 8, weight: .bold))
                                    Text("NEXT MODEL ❯")
                                        .font(.system(size: 9, weight: .black, design: .rounded))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.85))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                                )
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .help("Click to show the next Tesla vehicle model")
                        }
                        
                        // Direct Dropdown Selector for All 12 Tesla Models
                        Menu {
                            ForEach(TeslaCatalog.models) { model in
                                Button(action: {
                                    state.selectModel(model)
                                    switchModel(model)
                                }) {
                                    HStack {
                                        Text(model.name)
                                        if state.selectedModel.id == model.id {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(state.selectedModel.name)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                                Image(systemName: "chevron.down.circle.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.75))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(6)
                        }
                        .menuStyle(.borderlessButton)
                        
                        Text(state.selectedModel.subtitle)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.white.opacity(0.65))
                    }
                    
                    Spacer()
                    
                    // Vehicle Specs Chips
                    HStack(spacing: 8) {
                        ForEach(state.selectedModel.specs.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            VStack(alignment: .center, spacing: 1) {
                                Text(value)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Text(key.uppercased())
                                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.55))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.45))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                            .cornerRadius(6)
                        }
                    }
                    
                    // Quick Paint Finishing Palette (Instant 1-Click Ray Tracing Switch)
                    HStack(spacing: 8) {
                        ForEach(TeslaCatalog.paints) { paint in
                            Button(action: {
                                state.selectedPaint = paint
                                rayTracer.resetAccumulation()
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color(
                                            red: Double(paint.color.x),
                                            green: Double(paint.color.y),
                                            blue: Double(paint.color.z)
                                        ))
                                        .frame(width: 20, height: 20)
                                        .shadow(color: .black.opacity(0.4), radius: 2)
                                    
                                    if state.selectedPaint.id == paint.id {
                                        Circle()
                                            .stroke(Color.white, lineWidth: 2)
                                            .frame(width: 24, height: 24)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .help(paint.name)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .cornerRadius(6)
                    
                    // Navigation Mode (Orbit 3D vs Pan Move)
                    HStack(spacing: 2) {
                        Button(action: { state.navMode = .orbit }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Orbit")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(state.navMode == .orbit ? Color.white.opacity(0.25) : Color.clear)
                            .cornerRadius(5)
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .help("Orbit 3D: Drag to rotate view around car")
                        
                        Button(action: { state.navMode = .pan }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Pan")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(state.navMode == .pan ? Color.blue.opacity(0.8) : Color.clear)
                            .cornerRadius(5)
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .help("Pan Move: Drag to smoothly slide car across viewport")
                    }
                    .padding(2)
                    .background(Color.black.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .cornerRadius(6)
                    
                    // Quick Factory Privacy Glass Toggle Pill
                    Button(action: {
                        state.isPrivacyTintEnabled.toggle()
                        rayTracer.resetAccumulation()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: state.isPrivacyTintEnabled ? "circle.righthalf.filled" : "circle")
                                .font(.system(size: 11))
                                .foregroundColor(state.isPrivacyTintEnabled ? .indigo : .white.opacity(0.5))
                            Text(state.isPrivacyTintEnabled ? "Privacy Tint" : "Clear Glass")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(state.isPrivacyTintEnabled ? Color.indigo.opacity(0.45) : Color.black.opacity(0.45))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(state.isPrivacyTintEnabled ? Color.indigo.opacity(0.8) : Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Factory Privacy Glass on rear windows & panoramic roof (Model Y & Model X)")
                    
                    // Sidebar Studio Customizer Toggle
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isSidebarVisible.toggle() } }) {
                        HStack(spacing: 6) {
                            Image(systemName: "slider.horizontal.3")
                            Text("Studio Controls")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(isSidebarVisible ? Color.red.opacity(0.85) : Color.white.opacity(0.14))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                            .opacity(0.92)
                        WindowDragArea()
                    }
                )
                .cornerRadius(10)
                .padding(.top, 12)
                .padding(.horizontal, 16)
                
                Spacer()
                
                // Floating On-Screen Navigation Controls (Pan D-Pad, Recenter, Zoom In/Out, Gesture Legend)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            // D-Pad Grid for 1-Click Pan
                            VStack(spacing: 2) {
                                Button(action: {
                                    state.camera.pan(deltaX: 0, deltaY: 28)
                                    rayTracer.resetAccumulation()
                                }) {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 10, weight: .bold))
                                        .frame(width: 24, height: 18)
                                        .background(Color.white.opacity(0.15))
                                        .cornerRadius(3)
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                                .help("Pan Up")
                                
                                HStack(spacing: 2) {
                                    Button(action: {
                                        state.camera.pan(deltaX: 28, deltaY: 0)
                                        rayTracer.resetAccumulation()
                                    }) {
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 10, weight: .bold))
                                            .frame(width: 18, height: 24)
                                            .background(Color.white.opacity(0.15))
                                            .cornerRadius(3)
                                            .foregroundColor(.white)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Pan Left")
                                    
                                    Button(action: {
                                        let center = rayTracer.currentScene?.center ?? SIMD3<Float>(0, 0.7, 0)
                                        state.camera.recenter(center: center)
                                        rayTracer.resetAccumulation()
                                    }) {
                                        Image(systemName: "scope")
                                            .font(.system(size: 10, weight: .bold))
                                            .frame(width: 24, height: 24)
                                            .background(Color.white.opacity(0.25))
                                            .cornerRadius(4)
                                            .foregroundColor(.white)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Recenter pivot to vehicle")
                                    
                                    Button(action: {
                                        state.camera.pan(deltaX: -28, deltaY: 0)
                                        rayTracer.resetAccumulation()
                                    }) {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10, weight: .bold))
                                            .frame(width: 18, height: 24)
                                            .background(Color.white.opacity(0.15))
                                            .cornerRadius(3)
                                            .foregroundColor(.white)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Pan Right")
                                }
                                
                                Button(action: {
                                    state.camera.pan(deltaX: 0, deltaY: -28)
                                    rayTracer.resetAccumulation()
                                }) {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .bold))
                                        .frame(width: 24, height: 18)
                                        .background(Color.white.opacity(0.15))
                                        .cornerRadius(3)
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                                .help("Pan Down")
                            }
                            
                            // Zoom buttons (+ / −)
                            VStack(spacing: 3) {
                                Button(action: {
                                    state.camera.zoom(delta: 0.90)
                                    rayTracer.resetAccumulation()
                                }) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 10, weight: .bold))
                                        .frame(width: 24, height: 24)
                                        .background(Color.white.opacity(0.15))
                                        .cornerRadius(4)
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                                .help("Zoom in")
                                
                                Button(action: {
                                    state.camera.zoom(delta: 1.10)
                                    rayTracer.resetAccumulation()
                                }) {
                                    Image(systemName: "minus")
                                        .font(.system(size: 10, weight: .bold))
                                        .frame(width: 24, height: 24)
                                        .background(Color.white.opacity(0.15))
                                        .cornerRadius(4)
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                                .help("Zoom out")
                            }
                        }
                        
                        Text("Trackpad: 2 fingers Pan • Pinch Zoom • 1 finger Orbit\nMouse: Drag Orbit • Shift / Right drag Pan")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.60))
                            .lineSpacing(2)
                    }
                    .padding(8)
                    .background(
                        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).opacity(0.92)
                    )
                    .cornerRadius(8)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 2)
                
                // Bottom Camera Dock & Samples Progress Bar
                HStack(alignment: .center, spacing: 12) {
                    // Cinematic Tour & Turntable Controls
                    HStack(spacing: 6) {
                        // Cinematic Tour Showcase
                        Button(action: {
                            state.isTouring.toggle()
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: state.isTouring ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text(state.isTouring ? "Pause Tour" : "Cinematic Tour")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(state.isTouring ? Color.red.opacity(0.90) : Color.red.opacity(0.60))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help("Tour the vehicle with smooth cinematic camera angles")
                        
                        if state.isTouring {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 6, height: 6)
                                Text(state.tourStageName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("\(Int(state.tourProgress * 100))%")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.70))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(5)
                        }
                        
                        Divider().frame(height: 18).background(Color.white.opacity(0.25))
                        
                        // Turntable Toggle
                        Button(action: { state.isTurntable.toggle() }) {
                            HStack(spacing: 5) {
                                Image(systemName: state.isTurntable ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath")
                                Text("Turntable")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(state.isTurntable ? .black : .white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(state.isTurntable ? Color.white : Color.white.opacity(0.15))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        
                        Divider().frame(height: 18).background(Color.white.opacity(0.25))
                        
                        // Camera Presets
                        cameraPresetButton(title: "Hero 3/4", preset: .hero)
                        cameraPresetButton(title: "Side Profile", preset: .side)
                        cameraPresetButton(title: "Front Fascia", preset: .front)
                        cameraPresetButton(title: "Rear 3/4", preset: .rear)
                        cameraPresetButton(title: "Top Aero", preset: .top)
                        
                        Divider().frame(height: 18).background(Color.white.opacity(0.25))
                        
                        // Recenter Pivot
                        Button(action: {
                            let center = rayTracer.currentScene?.center ?? SIMD3<Float>(0, 0.7, 0)
                            state.camera.recenter(center: center)
                            rayTracer.resetAccumulation()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "scope")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Recenter")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                        .help("Recenter camera target to vehicle center")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).opacity(0.92)
                    )
                    .cornerRadius(8)
                    
                    Spacer()
                    
                    // Ray Tracing Sample Telemetry & Triangle Counter
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(state.sampleCount >= 256 ? Color.green : (state.isInteracting ? Color.orange : Color.blue))
                                .frame(width: 8, height: 8)
                            
                            Text(state.sampleCount >= 256 ? "Ray Traced (256/256 Converged)" :
                                    (state.isInteracting ? "Interactive RT (1 Sample)" : "Accumulating: \(state.sampleCount) / 256"))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        
                        Text("\(state.totalTriangles.formatted()) tris")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow).opacity(0.92)
                    )
                    .cornerRadius(8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
            
            // Right Side Controls Drawer (Collapsible)
            if isSidebarVisible {
                HStack {
                    Spacer()
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            // Section 1: Tesla Car Model Selector
                            VStack(alignment: .leading, spacing: 8) {
                                Text("ALL TESLA MODELS")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.6))
                                
                                ForEach(TeslaCatalog.models) { model in
                                    Button(action: {
                                        state.selectModel(model)
                                        switchModel(model)
                                    }) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(model.name)
                                                    .font(.system(size: 12, weight: state.selectedModel.id == model.id ? .bold : .medium))
                                                    .foregroundColor(.white)
                                                Text(model.subtitle)
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.white.opacity(0.55))
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            if state.selectedModel.id == model.id {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 13))
                                                    .foregroundColor(.red)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(state.selectedModel.id == model.id ? Color.white.opacity(0.18) : Color.white.opacity(0.05))
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            
                            Divider().background(Color.white.opacity(0.2))
                            
                            // Section 2: Metallic Paint & Finish
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("METALLIC PAINT & FINISH")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.6))
                                    Spacer()
                                    Text(state.selectedPaint.name)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 28), spacing: 8)], spacing: 8) {
                                    ForEach(TeslaCatalog.paints) { paint in
                                        Button(action: {
                                            state.selectedPaint = paint
                                            rayTracer.resetAccumulation()
                                        }) {
                                            ZStack {
                                                Circle()
                                                    .fill(Color(
                                                        red: Double(paint.color.x),
                                                        green: Double(paint.color.y),
                                                        blue: Double(paint.color.z)
                                                    ))
                                                    .frame(width: 26, height: 26)
                                                    .shadow(color: .black.opacity(0.4), radius: 2)
                                                
                                                if state.selectedPaint.id == paint.id {
                                                    Circle()
                                                        .stroke(Color.white, lineWidth: 2)
                                                        .frame(width: 30, height: 30)
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .help(paint.name)
                                    }
                                }
                                
                                sliderRow(title: "Metallic Flake", value: $state.metallic, range: 0.0...1.0)
                                sliderRow(title: "Paint Roughness", value: $state.roughness, range: 0.02...0.60)
                                sliderRow(title: "Clearcoat Gloss", value: $state.clearcoat, range: 0.0...1.0)
                            }
                            
                            Divider().background(Color.white.opacity(0.2))
                            
                            // Section 3: Nice Ground & Ray-Traced Reflections
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("STUDIO GROUND & REFLECTIONS")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.6))
                                    Spacer()
                                    Text("\(Int(state.groundReflectivity * 100))% Refl")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                
                                HStack(spacing: 6) {
                                    groundPresetButton(name: "Mirror Obsidian", refl: 0.88, rough: 0.02)
                                    groundPresetButton(name: "Studio Satin", refl: 0.55, rough: 0.12)
                                    groundPresetButton(name: "Matte Pedestal", refl: 0.20, rough: 0.35)
                                }
                                
                                sliderRow(title: "Ground Reflectivity", value: $state.groundReflectivity, range: 0.0...1.0)
                                sliderRow(title: "Ground Roughness", value: $state.groundRoughness, range: 0.0...0.45)
                            }
                            
                            Divider().background(Color.white.opacity(0.2))
                            
                            // Section 4: Factory Privacy Glass (Rear & Roof)
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("FACTORY PRIVACY GLASS (REAR & ROOF)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.6))
                                    Spacer()
                                    Toggle("", isOn: $state.isPrivacyTintEnabled)
                                        .toggleStyle(.switch)
                                        .labelsHidden()
                                        .scaleEffect(0.8)
                                }
                                
                                Text("Model Y & Model X feature dark rear privacy glass & UV panoramic roof as factory standard.")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.55))
                                    .lineLimit(2)
                                
                                if state.isPrivacyTintEnabled {
                                    HStack(spacing: 5) {
                                        privacyPresetButton(name: "Limo 5%", darkness: 0.95)
                                        privacyPresetButton(name: "Factory 20%", darkness: 0.80)
                                        privacyPresetButton(name: "Subtle 45%", darkness: 0.55)
                                        privacyPresetButton(name: "Clear", darkness: 0.15)
                                    }
                                    
                                    sliderRow(title: "Tint Darkness", value: $state.privacyTintDarkness, range: 0.10...0.95)
                                }
                            }
                            
                            Divider().background(Color.white.opacity(0.2))
                            
                            // Section 5: Apple Silicon Hardware Ray Tracing Diagnostics & Status
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "cpu.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.green)
                                    Text("APPLE SILICON HARDWARE RT")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.85))
                                    Spacer()
                                    Text("ENABLED")
                                        .font(.system(size: 8, weight: .black, design: .monospaced))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.green)
                                        .foregroundColor(.black)
                                        .cornerRadius(3)
                                }
                                
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text("RT Engine:")
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.6))
                                        Spacer()
                                        Text("Metal 3 Intersector")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundColor(.white)
                                    }
                                    HStack {
                                        Text("Acceleration:")
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.6))
                                        Spacer()
                                        Text("MTLAccelerationStructure")
                                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.85))
                                    }
                                    HStack {
                                        Text("Hardware Cores:")
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.6))
                                        Spacer()
                                        Text("RT Cores Active")
                                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.green)
                                    }
                                    HStack {
                                        Text("Triangles Traversed:")
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.6))
                                        Spacer()
                                        Text("\(state.totalTriangles.formatted()) tris")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundColor(.white)
                                    }
                                }
                                .padding(8)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(6)
                                
                                Text("Hardware Ray Tracing runs automatically on Apple Silicon GPU RT cores for primary, transmission, and ground reflection rays.")
                                    .font(.system(size: 8))
                                    .foregroundColor(.white.opacity(0.50))
                            }
                        }
                        .padding(16)
                    }
                    .frame(width: 290)
                    .background(
                        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                            .opacity(0.94)
                    )
                    .cornerRadius(12)
                    .padding(.top, 78)
                    .padding(.bottom, 64)
                    .padding(.trailing, 16)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .frame(minWidth: 1024, minHeight: 680)
        .onAppear { [weak rayTracer] in
            state.onMaterialChanged = {
                rayTracer?.resetAccumulation()
            }
            if let model = state.selectedModel as TeslaCarModel? {
                switchModel(model)
            }
        }
    }
    
    private func privacyPresetButton(name: String, darkness: Float) -> some View {
        Button(action: {
            state.isPrivacyTintEnabled = true
            state.privacyTintDarkness = darkness
            rayTracer.resetAccumulation()
        }) {
            Text(name)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(state.privacyTintDarkness == darkness && state.isPrivacyTintEnabled ? Color.indigo.opacity(0.7) : Color.white.opacity(0.12))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
    
    private func cameraPresetButton(title: String, preset: CameraPreset) -> some View {
        Button(action: {
            let radius = rayTracer.currentScene?.radius ?? 3.0
            let center = rayTracer.currentScene?.center ?? SIMD3<Float>(0, 0.7, 0)
            state.camera.applyPreset(preset, radius: radius, center: center)
            rayTracer.resetAccumulation()
        }) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.10))
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }
    
    private func groundPresetButton(name: String, refl: Float, rough: Float) -> some View {
        Button(action: {
            state.groundReflectivity = refl
            state.groundRoughness = rough
            rayTracer.resetAccumulation()
        }) {
            Text(name)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.12))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
    
    private func sliderRow(title: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
            Slider(value: value, in: range) {
                Text(title)
            }
            .accentColor(.red)
        }
    }
    
    private func switchToNextModel() {
        let allModels = TeslaCatalog.models
        let currentIndex = allModels.firstIndex(where: { $0.id == state.selectedModel.id }) ?? 0
        let nextIndex = (currentIndex + 1) % allModels.count
        let nextModel = allModels[nextIndex]
        state.selectModel(nextModel)
        switchModel(nextModel)
    }
    
    private func switchModel(_ model: TeslaCarModel) {
        let success = rayTracer.loadModel(filename: model.filename)
        if success {
            state.totalTriangles = rayTracer.currentScene?.totalTriangles ?? 0
            state.totalVertices = rayTracer.currentScene?.totalVertices ?? 0
            let radius = rayTracer.currentScene?.radius ?? 3.0
            let center = rayTracer.currentScene?.center ?? SIMD3<Float>(0, 0.7, 0)
            let preset = state.initialPreset ?? .hero
            state.camera.applyPreset(preset, radius: radius, center: center)
            state.initialPreset = nil
            rayTracer.resetAccumulation()
        }
    }
}

public struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

public struct WindowDragArea: NSViewRepresentable {
    public class DragView: NSView {
        public override var mouseDownCanMoveWindow: Bool { true }
        public override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
    
    public func makeNSView(context: Context) -> DragView {
        DragView()
    }
    
    public func updateNSView(_ nsView: DragView, context: Context) {}
}
