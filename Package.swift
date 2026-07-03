// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TTTranslator",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "tt-translator", targets: ["TTTranslator"])
    ],
    targets: [
        .target(name: "TTTranslatorCore"),
        .executableTarget(
            name: "TTTranslator",
            dependencies: ["TTTranslatorCore"]
        ),
        .testTarget(
            name: "TTTranslatorCoreTests",
            dependencies: ["TTTranslatorCore"]
        )
    ]
)
