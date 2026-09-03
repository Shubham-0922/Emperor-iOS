// swift-tools-version: 6.0
import PackageDescription

// The pure-logic half of the iOS client: stream parsing, wire models, request building.
//
// It is deliberately Foundation-only and imports no UI framework, so it compiles and tests
// on Linux. That matters because the streaming wire format is hand-rolled and full of
// edge cases (rollback markers, split tags, UTF-16 offsets) that are far cheaper to pin
// down with tests than to debug on a device.
//
// The Xcode app target compiles these same files directly (see project.yml), so nothing
// here needs `public` access.
let package = Package(
    name: "EmperorCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "EmperorCore", targets: ["EmperorCore"]),
    ],
    targets: [
        .target(name: "EmperorCore"),
        .testTarget(name: "EmperorCoreTests", dependencies: ["EmperorCore"]),
    ]
)
