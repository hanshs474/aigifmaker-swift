// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "AIGifMaker",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "AIGifMaker", targets: ["AIGifMaker"])],
    targets: [
        .target(name: "AIGifMaker"),
        .testTarget(name: "AIGifMakerTests", dependencies: ["AIGifMaker"]),
    ]
)
