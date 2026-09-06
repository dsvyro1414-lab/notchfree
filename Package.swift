// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchFree",
    platforms: [.macOS("14.6")],
    products: [
        .executable(name: "NotchFree", targets: ["NotchFree"]),
        .executable(name: "NotchFreeChecks", targets: ["NotchFreeChecks"])
    ],
    targets: [
        .target(name: "NotchFreeCore"),
        .executableTarget(name: "NotchFree", dependencies: ["NotchFreeCore"],
            linkerSettings: [.linkedFramework("IOBluetooth"), .linkedFramework("Carbon")]),
        .executableTarget(name: "NotchFreeChecks", dependencies: ["NotchFreeCore"])
    ],
    swiftLanguageModes: [.v5]
)
