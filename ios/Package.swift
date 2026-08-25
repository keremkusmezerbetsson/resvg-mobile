// swift-tools-version: 5.9
// Licensed under the Apache License, Version 2.0. See LICENSE and NOTICE.
import PackageDescription

let package = Package(
    name: "ResvgMobile",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(name: "ResvgMobile", targets: ["ResvgMobile"]),
        .library(name: "ResvgMobileUI", targets: ["ResvgMobileUI"]),
    ],
    targets: [
        // Local XCFramework produced by `./rust/build-ios.sh`.
        // GitHub consumers: run that script after clone, or use a Release zip
        // (see README / ios/ResvgMobileFFI.xcframework/BUILD.md).
        .binaryTarget(
            name: "resvg_mobileFFI",
            path: "ResvgMobileFFI.xcframework"
        ),
        .target(
            name: "ResvgMobile",
            dependencies: ["resvg_mobileFFI"],
            path: "Sources/ResvgMobile",
            exclude: [
                "Generated/resvg_mobileFFI.h",
                "Generated/resvg_mobileFFI.modulemap",
            ]
        ),
        .target(
            name: "ResvgMobileUI",
            dependencies: ["ResvgMobile"],
            path: "Sources/ResvgMobileUI"
        ),
    ]
)
