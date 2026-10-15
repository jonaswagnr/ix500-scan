// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ScanSnapLite",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ScanSnapLite", path: "Sources/ScanSnapLite")
    ]
)
