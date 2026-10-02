// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "E-Invoice Generator",
    defaultLocalization: "de",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "InvoiceKit", targets: ["InvoiceKit"]),
        .executable(name: "invoice-cli", targets: ["invoice-cli"]),
        .executable(name: "InvoiceApp", targets: ["InvoiceApp"]),
    ],
    targets: [
        .target(name: "InvoiceKit"),
        .executableTarget(name: "invoice-cli", dependencies: ["InvoiceKit"]),
        .executableTarget(name: "InvoiceApp", dependencies: ["InvoiceKit"]),
        .testTarget(
            name: "InvoiceKitTests",
            dependencies: ["InvoiceKit"]
        ),
    ]
)
