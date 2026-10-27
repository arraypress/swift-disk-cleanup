// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-disk-cleanup",
    // macOS only: LaunchServices answers "is this app installed", and the
    // installer readers drive hdiutil, xar and pkgutil.
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DiskCleanup", targets: ["DiskCleanup"]),
    ],
    dependencies: [
        .package(url: "https://github.com/arraypress/swift-sqlite-reader.git", from: "0.2.0"),
    ],
    targets: [
        // The rule catalogue is compiled in (Support/CatalogueData.swift), not
        // a resource bundle: a Homebrew-symlinked binary cannot find
        // Bundle.module, and a cleaner that cannot find its rules must not run.
        .target(name: "DiskCleanup", dependencies: [
            .product(name: "SQLiteReader", package: "swift-sqlite-reader"),
        ]),
        .testTarget(name: "DiskCleanupTests", dependencies: ["DiskCleanup"]),
    ]
)

// Swift 7's import rule, today: a file must import every module whose members
// it uses, rather than leaning on another file's imports.
for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + [.enableUpcomingFeature("MemberImportVisibility")]
}
