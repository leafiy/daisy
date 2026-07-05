// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DaisyTranslator",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "daisytranslator", targets: ["DaisyTranslator"])
    ],
    targets: [
        .target(name: "DaisyTranslatorCore"),
        .executableTarget(
            name: "DaisyTranslator",
            dependencies: ["DaisyTranslatorCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "DaisyTranslatorCoreTests",
            dependencies: ["DaisyTranslatorCore"]
        )
    ]
)
