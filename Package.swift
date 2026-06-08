// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Bookleet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Bookleet", targets: ["Bookleet"])
    ],
    targets: [
        .executableTarget(
            name: "Bookleet",
            path: "Sources/Bookleet"
        ),
        .testTarget(
            name: "BookleetTests",
            dependencies: ["Bookleet"],
            path: "Tests/BookleetTests"
        )
    ]
)
