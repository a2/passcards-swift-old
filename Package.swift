import PackageDescription

let package = Package(
    name: "Passcards",
    targets: [
        Target(name: "Passcards", dependencies: ["PasscardsServer"]),
        Target(name: "PasscardsServer")
    ],
    dependencies: [
        .Package(url: "https://github.com/IBM-Swift/Kitura.git", majorVersion: 0, minor: 33),
        .Package(url: "https://github.com/IBM-Swift/HeliumLogger.git", majorVersion: 0, minor: 17),
        .Package(url: "https://github.com/OpenKitten/MongoKitten.git", majorVersion: 1, minor: 7),
        .Package(url: "https://github.com/a2/shove.git", majorVersion: 0, minor: 1),
        .Package(url: "https://github.com/kylef/Commander.git", majorVersion: 0, minor: 5),
    ]
)
