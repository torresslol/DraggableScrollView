// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "DraggableScrollView",
    platforms: [
        .iOS(.v14),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "DraggableScrollView",
            targets: ["DraggableScrollView"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "DraggableScrollView",
            dependencies: []),
        .testTarget(
            name: "DraggableScrollViewTests",
            dependencies: ["DraggableScrollView"]),
    ]
) 