// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OldFunnyCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "OldFunnyCore", targets: ["OldFunnyCore"]),
               .executable(name: "OldFunnyProbe", targets: ["OldFunnyProbe"])],
    targets: [
        .target(name: "OldFunnyCore"),
        .executableTarget(name: "OldFunnyProbe", dependencies: ["OldFunnyCore"]),
        .testTarget(name: "OldFunnyCoreTests", dependencies: ["OldFunnyCore"])
    ]
)
