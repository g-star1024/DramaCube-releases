// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HongguoDesktopMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "HongguoCore", targets: ["HongguoCore"]),
        .library(name: "HongguoDesktopMac", targets: ["HongguoDesktopMac"]),
        .executable(name: "HongguoGateway", targets: ["HongguoGateway"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", .upToNextMajor(from: "2.0.0")),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", .upToNextMajor(from: "2.0.0")),
    ],
    targets: [
        .target(
            name: "HongguoCore",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup")
            ]
        ),
        .executableTarget(
            name: "HongguoGateway",
            dependencies: [
                .target(name: "HongguoCore"),
                .product(name: "Hummingbird", package: "hummingbird"),
            ]
        ),
        .target(
            name: "HongguoDesktopMac",
            dependencies: [
                .target(name: "HongguoCore")
            ]
        ),
        .testTarget(
            name: "HongguoCoreTests",
            dependencies: [
                .target(name: "HongguoCore")
            ]
        ),
    ]
)
