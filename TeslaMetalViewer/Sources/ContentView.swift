import SwiftUI

public struct ContentView: View {
    @ObservedObject var state: AppState
    let rayTracer: RayTracer
    @State private var inspector = true
    @State private var showComponents = false

    public var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TESLA / ASSET STUDIO").font(.caption).tracking(2).foregroundStyle(.secondary)
                        Text(state.selectedModel.name).font(.title2.weight(.semibold))
                    }
                    Spacer()
                    Button { state.selectModel(state.nextModel()); load() } label: {
                        Label("Next Model", systemImage: "chevron.right")
                    }.help("Load the next vehicle; wraps to the first after the last")
                    Button { fit(.hero) } label: { Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right") }
                    Button { inspector.toggle() } label: { Image(systemName: "sidebar.right") }
                }.padding(20)
                ZStack(alignment: .bottomLeading) {
                    MetalViewport(state: state, rayTracer: rayTracer)
                    VStack(alignment: .leading, spacing: 5) {
                        if let error = state.loadError { Text(error).foregroundStyle(.red) }
                        Text("Two fingers to orbit · Shift to pan · Pinch to zoom")
                        Text("\(state.totalTriangles.formatted()) triangles · \(state.sampleCount)/256 samples")
                    }.font(.caption).foregroundStyle(.secondary).padding(16).allowsHitTesting(false)
                }
                HStack {
                    ForEach([("Hero",CameraPreset.hero),("Side",.side),("Front",.front),("Rear",.rear),("Top",.top)], id: \.0) { title, preset in
                        Button(title) { fit(preset) }
                    }
                    Spacer()
                    Toggle("Tour", isOn: $state.isTouring).toggleStyle(.button)
                    Toggle("Turntable", isOn: $state.isTurntable).toggleStyle(.switch)
                }.padding(14)
            }
            if inspector {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        GroupBox("Vehicle") {
                            Picker("Model", selection: Binding(get: { state.selectedModel.id }, set: { id in
                                if let model = TeslaCatalog.models.first(where: { $0.id == id }) { state.selectModel(model); load() }
                            })) { ForEach(TeslaCatalog.models) { Text($0.name).tag($0.id) } }.labelsHidden().padding(8)
                        }
                        GroupBox("Source animation") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Select clips (\(state.selectedAnimations.count))").font(.caption)
                                    Spacer()
                                    Button("Clear") { state.selectedAnimations = [] }
                                }
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 8) {
                                        ForEach(state.animations) { clip in
                                            Toggle(clip.name.replacingOccurrences(of: "Animation", with: ""), isOn: Binding(
                                                get: { state.selectedAnimations.contains(clip.name) },
                                                set: { state.setAnimation(clip.name, enabled: $0) }
                                            )).toggleStyle(.checkbox)
                                        }
                                    }
                                }.frame(height: 160)
                                HStack {
                                    Button { state.toggleAnimationPlayback() } label: { Image(systemName: state.isPlayingAnimation ? "pause.fill" : "play.fill") }
                                    Button("Reset") { state.isPlayingAnimation = false; state.animationTime = 0 }
                                    Spacer()
                                    Text(String(format: "%.2f / %.2f s", state.animationTime, state.animationDuration)).monospacedDigit().font(.caption)
                                }.disabled(state.selectedAnimations.isEmpty)
                                Slider(value: $state.animationTime, in: 0...max(0.01,state.animationDuration)).disabled(state.selectedAnimations.isEmpty)
                                Text("Selected clips play together. Shorter clips hold their end pose. Clips controlling the same joint channel replace each other.").font(.caption).foregroundStyle(.secondary)
                            }.padding(8)
                        }
                        GroupBox("APK runtime effects") {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Driving road", isOn: $state.isDriving)
                                if state.isDriving { control("Speed (mph)", value: $state.drivingSpeed, range: -20...60) }
                                Picker("Climate", selection: $state.climateMode) {
                                    Text("Off").tag(Float(0)); Text("Cool").tag(Float(1)); Text("Heat").tag(Float(2))
                                }.disabled(!state.supportsClimate)
                                Toggle("Charging cable + flow", isOn: $state.isCharging).disabled(!state.supportsCharging)
                                    .onChange(of: state.isCharging) { _, enabled in
                                        if enabled, let clip = state.animations.first(where: { $0.name.lowercased().contains("chargeport") }) {
                                            state.setAnimation(clip.name, enabled: true); state.animationTime = max(state.animationTime,clip.duration)
                                        }
                                    }
                                Text("Road, airflow and cable effects ported from the APK scripts and shaders. Opaque body panels occlude airflow; glass transmits it.").font(.caption).foregroundStyle(.secondary)
                            }.padding(8)
                        }
                        GroupBox("Finish") {
                            VStack(alignment: .leading, spacing: 12) {
                                Picker("Paint", selection: Binding(get: { state.selectedPaint.id }, set: { id in
                                    if let paint = TeslaCatalog.paints.first(where: { $0.id == id }) { state.selectedPaint = paint }
                                })) { ForEach(TeslaCatalog.paints) { Text($0.name).tag($0.id) } }
                                control("Metallic", value: $state.metallic, range: 0...1)
                                control("Roughness", value: $state.roughness, range: 0.03...1)
                                control("Clearcoat", value: $state.clearcoat, range: 0...1)
                                Picker("Window surrounds", selection: $state.windowTrim) {
                                    ForEach(WindowTrim.allCases) { Text($0.rawValue).tag($0) }
                                }
                                control("Headlight reflection", value: $state.headlightReflection, range: 0...1)
                                Toggle("Privacy tint override", isOn: $state.isPrivacyTintEnabled)
                                if state.isPrivacyTintEnabled { control("Tint", value: $state.privacyTintDarkness, range: 0...1) }
                            }.padding(8)
                        }
                        GroupBox("Camera tour") {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Play tour", isOn: $state.isTouring).toggleStyle(.switch)
                                control("Tour speed", value: $state.tourSpeed, range: 0.25...2)
                                if state.isTouring {
                                    Text(state.tourStageName).font(.caption)
                                    ProgressView(value: Double(state.tourProgress))
                                    Button("Restart tour") { state.camera.tourTime = 0; state.tourProgress = 0 }
                                }
                            }.padding(8)
                        }
                        GroupBox("Studio") {
                            VStack(alignment: .leading, spacing: 12) {
                                Picker("Lighting", selection: $state.lighting) {
                                    ForEach(LightingPreset.allCases) { Text($0.rawValue).tag($0) }
                                }
                                control("Exposure", value: $state.exposure, range: 0.4...2.5)
                                control("Floor reflection", value: $state.groundReflectivity, range: 0...1)
                                control("Floor roughness", value: $state.groundRoughness, range: 0.02...0.5)
                                Picker("Drag mode", selection: $state.navMode) { ForEach(NavigationMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                            }.padding(8)
                        }
                        DisclosureGroup("Component materials", isExpanded: $showComponents) {
                            if showComponents {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array((rayTracer.currentScene?.geometries ?? []).enumerated()), id: \.offset) { _, g in
                                    if g.isGround == 0 {
                                        VStack(alignment: .leading) {
                                            Text(g.componentName.components(separatedBy: "/").last ?? "").font(.caption.weight(.medium))
                                            Text(g.sourceMaterial).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                                        }
                                    }
                                }
                            }
                            }
                        }
                    }.padding(20)
                }.frame(width: 340)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 960, minHeight: 620)
        .onAppear {
            state.onMaterialChanged = { rayTracer.resetAccumulation() }
            let startTour = state.isTouring
            load()
            state.isTouring = startTour
        }
    }
    private func control(_ name: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(name); Spacer(); Text(String(format: "%.2f", value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary) }.font(.caption)
            Slider(value: value, in: range)
        }
    }
    private func fit(_ preset: CameraPreset) {
        state.isTouring = false; state.isTurntable = false
        state.camera.applyPreset(preset, radius: rayTracer.currentScene?.radius ?? 3, center: rayTracer.currentScene?.center ?? .zero)
        rayTracer.resetAccumulation()
    }
    private func load() {
        state.isPlayingAnimation = false; state.selectedAnimations = []
        state.isCharging = false; state.climateMode = 0; state.isDriving = false
        rayTracer.wheelDegrees = 0; rayTracer.effectTime = 0
        if rayTracer.loadModel(filename: state.selectedModel.filename) {
            state.loadError = nil
            state.supportsClimate = !(rayTracer.currentScene?.climatePlanes.isEmpty ?? true)
            state.supportsCharging = rayTracer.currentScene?.hasChargingCable ?? false
            state.animations = rayTracer.currentScene?.animations ?? []
            state.totalTriangles = rayTracer.currentScene?.totalTriangles ?? 0
            state.totalVertices = rayTracer.currentScene?.totalVertices ?? 0
            state.frameLoadedModel(radius: rayTracer.currentScene?.radius ?? 3,
                                   center: rayTracer.currentScene?.center ?? .zero,
                                   preset: state.initialPreset ?? .hero)
            state.initialPreset = nil
        } else { state.loadError = "Unable to load \(state.selectedModel.filename)" }
    }
}
