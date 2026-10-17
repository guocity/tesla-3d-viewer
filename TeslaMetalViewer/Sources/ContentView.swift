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
                            
                            Text("APPLE SILICON HARDWARE RT")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.12))
                                .cornerRadius(4)
                                .foregroundColor(.white.opacity(0.85))
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
                
                // Bottom Camera Dock & Samples Progress Bar
                HStack(alignment: .center, spacing: 12) {
                    // Camera Presets
                    HStack(spacing: 6) {
                        cameraPresetButton(title: "Hero 3/4", preset: .hero)
                        cameraPresetButton(title: "Side Profile", preset: .side)
                        cameraPresetButton(title: "Front Fascia", preset: .front)
                        cameraPresetButton(title: "Rear 3/4", preset: .rear)
                        cameraPresetButton(title: "Top Aero", preset: .top)
                        
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
    
    private func switchModel(_ model: TeslaCarModel) {
        let success = rayTracer.loadModel(filename: model.filename)
        if success {
            state.totalTriangles = rayTracer.currentScene?.totalTriangles ?? 0
            state.totalVertices = rayTracer.currentScene?.totalVertices ?? 0
            let radius = rayTracer.currentScene?.radius ?? 3.0
            let center = rayTracer.currentScene?.center ?? SIMD3<Float>(0, 0.7, 0)
            state.camera.applyPreset(.hero, radius: radius, center: center)
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
