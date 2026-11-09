// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Parchi",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "ParchiCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(
            name: "Parchi",
            dependencies: ["ParchiCore"],
            // Everything runs on the main thread. Swift 6 mode adds a runtime isolation check
            // to AppKit callbacks that crashes on macOS 27 with the Swift 6.2 toolchain.
            swiftSettings: [.defaultIsolation(MainActor.self), .swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "ParchiCoreCheck",
            dependencies: ["ParchiCore"]
        ),
    ]
)
