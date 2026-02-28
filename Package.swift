// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "YTDLFront",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(name: "YTDLFront", targets: ["YTDLFront"])
    ],
    targets: [
        .executableTarget(
            name: "YTDLFront",
            path: "Sources/YTDLFront"
        )
    ]
)
