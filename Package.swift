// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MenuFold",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "MenuFold", targets: ["MenuFold"])
    ],
    targets: [
        .executableTarget(
            name: "MenuFold",
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "MenuFoldTests",
            dependencies: ["MenuFold"]
        )
    ],
    swiftLanguageModes: [.v5]
)
