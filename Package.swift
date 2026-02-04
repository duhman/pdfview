// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "PDFView",
    platforms: [
        .macOS("26.2")
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
