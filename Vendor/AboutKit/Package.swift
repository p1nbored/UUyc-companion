// swift-tools-version:5.9
// Local stand-in for the private AboutKit, for building UUyc-companion from source. Not the real module.
import PackageDescription

let package = Package(
    name: "AboutKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AboutKit", targets: ["AboutKit"])],
    targets: [.target(name: "AboutKit", resources: [.copy("Resources/STUB.txt")])]
)
