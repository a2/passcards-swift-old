import PackageDescription

let package = Package(
    name: "Passcards",
    targets: [
        Target(name: "App", dependencies: ["Server"]),
        Target(name: "Server")
    ],
    dependencies: [
        .Package(url: "https://github.com/IBM-Swift/Kitura.git", majorVersion: 0, minor: 33),
        .Package(url: "https://github.com/IBM-Swift/HeliumLogger.git", majorVersion: 0, minor: 17),
        .Package(url: "https://github.com/OpenKitten/MongoKitten.git", majorVersion: 1, minor: 7),
    ]
)
