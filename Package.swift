// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PinShot",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "PinShot",
            targets: ["PinShot"]
        )
    ],
    targets: [
        .executableTarget(
            name: "PinShot",
            path: "Sources/PinShot"
        )
    ]
)
