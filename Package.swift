// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "swift-argsbarg",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "ArgsBarg", targets: ["ArgsBarg"]),
        .executable(name: "ArgsBargMinimal", targets: ["ArgsBargMinimal"]),
        .executable(name: "ArgsBargNested", targets: ["ArgsBargNested"]),
    ],
    targets: [
        .target(
            name: "ArgsBarg",
            path: "Sources/ArgsBarg"
        ),
        .executableTarget(
            name: "ArgsBargMinimal",
            dependencies: ["ArgsBarg"],
            path: "Examples/Minimal"
        ),
        .executableTarget(
            name: "ArgsBargNested",
            dependencies: ["ArgsBarg"],
            path: "Examples/Nested"
        ),
        .testTarget(
            name: "ArgsBargTests",
            dependencies: ["ArgsBarg"],
            path: "Tests/ArgsBargTests"
        ),
    ]
)
