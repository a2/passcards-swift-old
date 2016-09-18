import PackageDescription

let package = Package(
    name: "Passcards",
    dependencies: [
        .Package(url: "https://github.com/vapor/vapor.git", majorVersion: 1),
        .Package(url: "https://github.com/OpenKitten/MongoKitten.git", majorVersion: 1),
        .Package(url: "https://github.com/a2/swift-apns.git", majorVersion: 2, minor: 1),
    ],
    exclude: [
        "Config",
        "Database",
        "Localization",
        "Public",
        "Resources",
        "Tests",
    ]
)
