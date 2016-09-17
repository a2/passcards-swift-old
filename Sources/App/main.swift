import Vapor
import HTTP
import FluentMongo
import Foundation
import APNS

let mongo = try MongoDriver(
    database: "test",
    user: "user1",
    password: "pswd1",
    host: "0.0.0.0",
    port: 27017
)
let db = Database(mongo)
Database.default = db

let drop = Droplet(database: db)

drop.get("/:passId") { request in
    guard let fullPassId = request.parameters["passId"]?.string,
        fullPassId.hasSuffix(".pkpass"),
        let extensionIndex = fullPassId.characters.index(of: "."),
        fullPassId[extensionIndex ..< fullPassId.endIndex] == ".pkpass"
    else {
        return Response(status: .notFound)
    }

    let passId = fullPassId[fullPassId.startIndex ..< extensionIndex]

    let pass: Pass
    do {
        let localPass = try Pass.query()
            .filter("vanityId", passId)
            .first()
        if let localPass = localPass {
            pass = localPass
        } else {
            return Response(status: .notFound)
        }
    }

    let body: Body
    let status: Status

    if pass.data.isEmpty {
        body = .data([])
        status = .noContent
    } else {
        body = .data(pass.data)
        status = .ok
    }

    let headers: [HeaderKey: String] = [
        "Last-Modified": RFC1123.shared.formatter.string(from: pass.updatedAt),
        "Content-Type": "application/vnd.apple.pkpass",
    ]
    return Response(status: status, headers: headers, body: body)
}

drop.post("/:passId") { request in
    guard let masterKey = drop.config["app", "master-key"]?.string,
        request.headers["Authorization"] == "Token \(masterKey)"
    else {
        return Response(status: .unauthorized)
    }

    guard let fullPassId = request.parameters["passId"]?.string,
        fullPassId.hasSuffix(".pkpass"),
        let extensionIndex = fullPassId.characters.index(of: "."),
        fullPassId[extensionIndex ..< fullPassId.endIndex] == ".pkpass"
    else {
        return Response(status: .notFound)
    }

    let passId = fullPassId[fullPassId.startIndex ..< extensionIndex]

    let existingPass = try Pass.query()
        .filter("vanityId", passId)
        .first()
    if existingPass != nil {
        return Response(status: .seeOther, headers: ["Location": request.uri.description])
    }

    guard let query = request.query,
        let authenticationToken = query["authenticationToken"]?.string,
        let passTypeIdentifier = query["passTypeIdentifier"]?.string,
        let serialNumber = query["serialNumber"]?.string,
        let bodyData = request.body.bytes,
        !bodyData.isEmpty
    else {
        return Response(status: .badRequest)
    }

    var pass = Pass(vanityId: passId, authenticationToken: authenticationToken, passTypeIdentifier: passTypeIdentifier, serialNumber: serialNumber, data: bodyData)
    try pass.save()

    return Response(status: .created)
}

drop.put("/:passId") { request in
    guard let masterKey = drop.config["app", "master-key"]?.string,
        request.headers["Authorization"] == "Token \(masterKey)"
    else {
        return Response(status: .unauthorized)
    }

    guard let fullPassId = request.parameters["passId"]?.string,
        fullPassId.hasSuffix(".pkpass"),
        let extensionIndex = fullPassId.characters.index(of: "."),
        fullPassId[extensionIndex ..< fullPassId.endIndex] == ".pkpass"
    else {
        return Response(status: .notFound)
    }

    let passId = fullPassId[fullPassId.startIndex ..< extensionIndex]

    let oldPass: Pass
    do {
        let localPass = try Pass.query()
            .filter("vanityId", passId)
            .first()
        if let localPass = localPass {
            oldPass = localPass
        } else {
            return Response(status: .notFound)
        }
    }

    guard let bodyData = request.body.bytes,
        !bodyData.isEmpty
    else {
        return Response(status: .badRequest)
    }

    try oldPass.delete()

    var newPass = Pass(vanityId: oldPass.vanityId, authenticationToken: oldPass.authenticationToken, passTypeIdentifier: oldPass.passTypeIdentifier, serialNumber: oldPass.serialNumber, data: bodyData)
    try newPass.save()




    let network = APNSNetwork()
    network.sendPushWith(message: <#T##ApplePushMessage#>)

    return Response(status: .ok)
}

drop.collection(WalletCollection.self)

drop.run()
