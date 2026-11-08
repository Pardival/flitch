// swift-tools-version: 6.2
import PackageDescription

/// FlitchKit holds all of Flitch's logic. Only `FlitchStage` may import AppKit,
/// so everything else can be tested headless with `swift test`.
let package = Package(
    name: "FlitchKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FlitchCore", targets: ["FlitchCore"]),
        .library(name: "FlitchProviders", targets: ["FlitchProviders"]),
        .library(name: "FlitchVoice", targets: ["FlitchVoice"]),
        .library(name: "FlitchMemory", targets: ["FlitchMemory"]),
        .library(name: "FlitchCharacter", targets: ["FlitchCharacter"]),
        .library(name: "FlitchStage", targets: ["FlitchStage"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(name: "FlitchCore", resources: [.process("Resources")]),
        .target(name: "FlitchProviders", dependencies: ["FlitchCore", "FlitchVoice"], resources: [.process("Resources")]),
        .target(name: "FlitchVoice", dependencies: ["FlitchCore"]),
        .target(name: "FlitchMemory", dependencies: ["FlitchCore", .product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "FlitchCharacter", dependencies: ["FlitchCore"]),
        .target(name: "FlitchStage", dependencies: ["FlitchCore", "FlitchCharacter"], resources: [.process("Resources")]),

        .testTarget(name: "FlitchCoreTests", dependencies: ["FlitchCore"], exclude: ["__Snapshots__"]),
        .testTarget(name: "FlitchProvidersTests", dependencies: ["FlitchProviders", "FlitchVoice"], resources: [.copy("Fixtures")]),
        .testTarget(name: "FlitchVoiceTests", dependencies: ["FlitchVoice"]),
        .testTarget(name: "FlitchMemoryTests", dependencies: ["FlitchMemory"]),
        .testTarget(name: "FlitchCharacterTests", dependencies: ["FlitchCharacter"]),
        .testTarget(name: "FlitchStageTests", dependencies: ["FlitchStage"]),
    ]
)
