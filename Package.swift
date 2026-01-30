// swift-tools-version:6.1

import PackageDescription

let package = Package(
    name: "PDFView",
    platforms: [
        .macOS("15.0")
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
