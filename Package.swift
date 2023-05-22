// swift-tools-version:5.6

import PackageDescription

let package = Package(
    name: "Logger",
    
    platforms: [
        .macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v5)
    ],
    
    products: [
        .library(
            name: "Logger",
            targets: ["Logger"]),
        .library(
            name: "LoggerUI",
            targets: ["LoggerUI"]),
        .library(
            name: "LoggerTestSupport",
            targets: ["LoggerTestSupport"])
    ],
    
    dependencies: [
        .package(url: "https://github.com/elegantchaos/ActionBuilderPlugin.git", from: "1.0.8"),
        .package(url: "https://github.com/elegantchaos/SwiftFormatterPlugin.git", from: "1.0.3"),

    ],
    
    targets: [
        .target(
            name: "Logger",
            dependencies: []),
        .target(
            name: "LoggerUI",
            dependencies: ["Logger"]),
        .target(
            name: "LoggerTestSupport",
            dependencies: ["Logger"]),
        .testTarget(
            name: "LoggerTests",
            dependencies: ["Logger", "LoggerTestSupport"]),
    ]
  )


import Foundation
if ProcessInfo.processInfo.environment["RESOLVE_COMMAND_PLUGINS"] != nil {
    package.dependencies.append(contentsOf: [
        .package(url: "https://github.com/elegantchaos/ActionBuilderPlugin.git", from: "1.0.7"),
        .package(url: "https://github.com/elegantchaos/SwiftFormatterPlugin.git", from: "1.0.2")
    ])
}
