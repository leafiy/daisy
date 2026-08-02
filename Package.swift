// swift-tools-version: 5.10
import PackageDescription

var products: [Product] = []
var targets: [Target] = [
    .target(name: "DaisyTranslatorCore"),
    .testTarget(
        name: "DaisyTranslatorCoreTests",
        dependencies: ["DaisyTranslatorCore"]
    )
]

// The app target needs AppKit/SwiftUI; DaisyTranslatorCore + tests also build on Linux.
#if os(macOS)
products.append(.executable(name: "daisytranslator", targets: ["DaisyTranslator"]))
targets.append(
    .executableTarget(
        name: "DaisyTranslator",
        dependencies: [
            "DaisyTranslatorCore",
            .product(name: "LeafiyUI", package: "leafiy-ui"),
            .product(name: "LeafiyUICore", package: "leafiy-ui")
        ],
        resources: [.process("Resources")]
    )
)
targets.append(
    .testTarget(
        name: "DaisyTranslatorTests",
        dependencies: ["DaisyTranslator"]
    )
)
#endif

let package = Package(
    name: "DaisyTranslator",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: products,
    dependencies: [
        .package(path: "../leafiy-ui")
    ],
    targets: targets
)
