// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "IX500Scan",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "IX500Scan", path: "Sources/IX500Scan")
    ]
)
