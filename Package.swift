// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WorkspaceBar",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "Shiftland", targets: ["WorkspaceBar"])],
    targets: [
        .executableTarget(name: "WorkspaceBar"),
        .testTarget(name: "WorkspaceBarTests", dependencies: ["WorkspaceBar"])
    ]
)
