// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TeslaMetalViewer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TeslaMetalViewer", targets: ["TeslaMetalViewer"])
    ],
    targets: [
        .executableTarget(
            name: "TeslaMetalViewer",
            path: "Sources"
        )
    ]
)
