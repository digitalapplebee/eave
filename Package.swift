// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Eave",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Eave", targets: ["Eave"])],
    targets: [
        .target(name: "EaveCore", path: "Eave/Core"),
        .executableTarget(name: "Eave", dependencies: ["EaveCore"], path: "Eave/App"),
        .testTarget(name: "EaveCoreTests", dependencies: ["EaveCore"], path: "Tests")
    ],
    swiftLanguageModes: [.v6]
)
