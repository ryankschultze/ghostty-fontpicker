// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FontPicker",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "fontpicker", targets: ["fontpicker"]),
        .library(name: "FontPickerCore", targets: ["FontPickerCore"]),
    ],
    targets: [
        // Font discovery, OpenType feature probing and Ghostty config handling. No UI.
        .target(name: "FontPickerCore"),
        // The picker window plus a small CLI over the same core.
        .executableTarget(name: "fontpicker", dependencies: ["FontPickerCore"]),
        .testTarget(name: "FontPickerCoreTests", dependencies: ["FontPickerCore"]),
    ]
)
