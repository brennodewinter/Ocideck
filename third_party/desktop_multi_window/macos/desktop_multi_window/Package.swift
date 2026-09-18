// swift-tools-version: 5.9
import Foundation
import PackageDescription

// FlutterMacOS is injected by Flutter and is therefore unavailable to a plain
// `swift test`. This switch isolates the AppKit-only regression tests without
// changing the package graph used by Flutter consumers.
let styleTestsOnly = ProcessInfo.processInfo.environment["OCIDECK_STYLE_TESTS"] == "1"

let package = Package(
    name: "desktop_multi_window",
    platforms: [
        .macOS("10.11")
    ],
    products: styleTestsOnly
        ? [.library(name: "DesktopMultiWindowSupport", targets: ["DesktopMultiWindowSupport"])]
        : [.library(name: "desktop-multi-window", targets: ["desktop_multi_window"])],
    dependencies: [],
    targets: styleTestsOnly
        ? [
            .target(name: "DesktopMultiWindowSupport"),
            .testTarget(
                name: "DesktopMultiWindowSupportTests",
                dependencies: ["DesktopMultiWindowSupport"]
            ),
        ]
        : [
            .target(
                name: "desktop_multi_window",
                dependencies: ["DesktopMultiWindowSupport"]
            ),
            .target(name: "DesktopMultiWindowSupport"),
        ]
)
