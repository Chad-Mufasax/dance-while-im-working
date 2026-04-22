// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DanceWhileImWorking",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DanceWhileImWorking", targets: ["DanceWhileImWorking"])
    ],
    targets: [
        .executableTarget(
            name: "DanceWhileImWorking",
            path: "Sources/DanceWhileImWorking"
        )
    ]
)
