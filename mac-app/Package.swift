// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "TotalImageAssetClassifier",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "TotalImageAssetClassifier",
            targets: ["TotalImageAssetClassifier"]
        )
    ],
    targets: [
        .executableTarget(
            name: "TotalImageAssetClassifier",
            path: "Sources/TotalImageAssetClassifier"
        )
    ]
)
