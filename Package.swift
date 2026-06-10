// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeskCat",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/warrenm/GLTFKit2", exact: "0.5.15")
    ],
    targets: [
        .executableTarget(
            name: "DeskCat",
            dependencies: [
                .product(name: "GLTFKit2", package: "GLTFKit2")
            ],
            resources: [
                .copy("Resources/cat.glb")
            ]
        )
    ]
)
