// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FreeClean",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "freeclean", targets: ["freeclean"]),
        .executable(name: "FreeCleanApp", targets: ["FreeCleanApp"]),
        .library(name: "CleanCore", targets: ["CleanCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "CleanCore"),
        .executableTarget(
            name: "freeclean",
            dependencies: ["CleanCore", .product(name: "ArgumentParser", package: "swift-argument-parser")]
        ),
        .executableTarget(name: "FreeCleanApp", dependencies: ["CleanCore"]),
        // Plain executable instead of a test target: XCTest/Swift Testing need full Xcode.
        .executableTarget(name: "freeclean-selftest", dependencies: ["CleanCore"], path: "Tests/SelfTest"),
    ]
)
