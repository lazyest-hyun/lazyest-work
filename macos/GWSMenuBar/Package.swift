// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GWSMenuBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GWSMenu", targets: ["GWSMenuBar"])
    ],
    dependencies: [
        .package(url: "https://github.com/google/GoogleSignIn-iOS.git", from: "9.0.0"),
        .package(url: "https://github.com/google/GTMAppAuth.git", from: "5.0.0")
    ],
    targets: [
        .executableTarget(
            name: "GWSMenuBar",
            dependencies: [
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
                .product(name: "GTMAppAuth", package: "GTMAppAuth")
            ],
            path: "Sources/GWSMenuBar",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
