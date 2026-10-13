// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ApplePhotoExport",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PhotoExport", targets: ["PhotoExport"])],
    targets: [
        .target(name: "ExportCore"),
        .executableTarget(name: "PhotoExport", dependencies: ["ExportCore"]),
        .testTarget(name: "ExportCoreTests", dependencies: ["ExportCore"])
    ]
)
