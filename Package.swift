// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HongguoDesktopMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "HongguoCore", targets: ["HongguoCore"]),
        .library(name: "HongguoGatewayCore", targets: ["HongguoGatewayCore"]),
        .library(name: "HongguoDesktopMac", targets: ["HongguoDesktopMac"]),
        .executable(name: "HongguoGateway", targets: ["HongguoGateway"]),
        .executable(name: "HongguoMacApp", targets: ["HongguoMacApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", .upToNextMajor(from: "2.0.0")),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", .upToNextMajor(from: "2.0.0")),
        // libmpv 播放内核（M2）：MPVKit 提供 MPVKit SwiftUI 视图 + LibMPV C 绑定 + FFmpeg 全家桶。
        .package(url: "https://github.com/karelrooted/MPVKit.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "HongguoCore",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup")
            ]
        ),
        .target(
            name: "HongguoGatewayCore",
            dependencies: [
                .target(name: "HongguoCore"),
                .product(name: "Hummingbird", package: "hummingbird"),
            ]
        ),
        .executableTarget(
            name: "HongguoGateway",
            dependencies: [
                .target(name: "HongguoGatewayCore")
            ]
        ),
        .target(
            name: "HongguoDesktopMac",
            dependencies: [
                .target(name: "HongguoCore"),
                .target(name: "HongguoGatewayCore"),
                .product(name: "MPVKit", package: "MPVKit"),
            ]
        ),
        // App 可执行入口：打包脚本将其装入 Hongguo.app/Contents/MacOS。
        .executableTarget(
            name: "HongguoMacApp",
            dependencies: [
                .target(name: "HongguoDesktopMac")
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
