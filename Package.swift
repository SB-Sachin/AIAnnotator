// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AIAnnotator",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AnnotatorCore", path: "Sources/AnnotatorCore"),
        .executableTarget(name: "AIAnnotator", dependencies: ["AnnotatorCore"], path: "Sources/AIAnnotator"),
        .testTarget(name: "AnnotatorCoreTests", dependencies: ["AnnotatorCore"], path: "Tests/AnnotatorCoreTests"),
    ],
    swiftLanguageModes: [.v5]
)
