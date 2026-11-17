// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacView",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        .executableTarget(
            name: "MacView",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/MacView",
            linkerSettings: [
                // The binary ships inside MacView.app and must find
                // Sparkle.framework at Contents/Frameworks/. dyld searches
                // rpaths relative to the binary; without this the framework
                // only resolves when it happens to sit next to the binary
                // (which SPM-built apps don't do). build.sh embed_sparkle()
                // copies the framework into Contents/Frameworks/.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        )
    ]
)
