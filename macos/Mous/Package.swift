// swift-tools-version: 5.9

import Foundation
import PackageDescription

let infoPlistPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/Mous/Info.plist")
    .path

let package = Package(
    name: "Mous",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Mous", targets: ["Mous"]),
        .executable(name: "MousCoreCheck", targets: ["MousCoreCheck"]),
        .library(name: "MousCore", targets: ["MousCore"]),
    ],
    targets: [
        .target(name: "MousCore"),
        .executableTarget(
            name: "Mous",
            dependencies: ["MousCore"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlistPath,
                ])
            ]
        ),
        .executableTarget(
            name: "MousCoreCheck",
            dependencies: ["MousCore"],
            path: "Tests/MousCoreCheck"
        ),
    ]
)
