// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "PDFView",
    platforms: [
        .macOS("14.2")
    ],
    products: [
        .executable(
            name: "PDFView",
            targets: ["PDFViewApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "PDFViewApp",
            path: "Sources"
        )
    ]
)
