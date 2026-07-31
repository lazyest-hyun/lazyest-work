// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LazyestWork",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "LazyestWorkCore", targets: ["LazyestWorkCore"]),
        .executable(name: "LazyestWork", targets: ["LazyestWork"])
    ],
    dependencies: [
        .package(url: "https://github.com/google/GoogleSignIn-iOS.git", from: "9.0.0"),
        .package(url: "https://github.com/google/GTMAppAuth.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "LazyestWorkCore",
            path: "Sources/LazyestWorkCore"
        ),
        .executableTarget(
            name: "LazyestWork",
            dependencies: [
                "LazyestWorkCore",
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
                .product(name: "GTMAppAuth", package: "GTMAppAuth")
            ],
            path: "Sources/LazyestWork",
            resources: [
                .process("Resources/FocusShortcuts")
            ]
        )
    ]
)
