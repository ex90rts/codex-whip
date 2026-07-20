// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexWhip",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexWhip", targets: ["CodexWhip"])
    ],
    targets: [
        .executableTarget(
            name: "CodexWhip",
            path: "Sources/CodexWhip",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CodexWhipTests",
            dependencies: ["CodexWhip"],
            path: "Tests/CodexWhipTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
