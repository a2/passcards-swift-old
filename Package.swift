import PackageDescription

let package = Package(
    name: "Passcards",
    dependencies: [
        .Package(url: "https://github.com/IBM-Swift/Kitura.git", majorVersion: 0),
        .Package(url: "https://github.com/IBM-Swift/HeliumLogger.git", majorVersion: 0),
        .Package(url: "https://github.com/OpenKitten/MongoKitten.git", majorVersion: 1),
    ]
)
