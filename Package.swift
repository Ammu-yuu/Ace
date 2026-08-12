// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AcePet",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "AcePet",
            path: "Sources/AcePet"
        )
    ],
    // Use the Swift 5 language mode for now to keep iteration fast.
    // We'll tighten to full Swift 6 strict concurrency in a later pass.
    swiftLanguageModes: [.v5]
)
