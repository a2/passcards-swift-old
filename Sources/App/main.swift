import Vapor
import HTTP
import MongoKitten
import Foundation
import APNS

let mongo: MongoKitten.Server
do {
    mongo = try Server("mongodb://user1:pswd1@0.0.0.0:27017", automatically: true)
} catch {
    print("MongoDB is not available on the given host and port")
    exit(1)
}

let database = mongo["test"]
let passes = database["passes"]
let installations = database["installations"]

let drop = Droplet()

func parseVanityId(from fileName: String) -> String? {
    guard fileName.lowercased().hasSuffix(".pkpass"),
        let extensionIndex = fileName.characters.index(of: "."),
        fileName[extensionIndex ..< fileName.endIndex].lowercased() == ".pkpass"
    else {
        return nil
    }

    return fileName[fileName.startIndex ..< extensionIndex]
}

func findPassDocument(withVanityId vanityId: String) throws -> Document? {
    return try passes.findOne(matching: "vanityId" == vanityId)
}

func validateMasterAuthorization(for request: Request) -> Bool {
    guard let masterKey = drop.config["app", "master-key"]?.string, !masterKey.isEmpty else {
        return true
    }

    return request.headers["Authorization"] == "Token \(masterKey)"
}

func fetchDeviceTokens(for passId: BSON.Value) throws -> [String] {
    let cursor = try installations.find(matching: "passId" == passId)

    var deviceTokens = [String]()
    for installation in cursor {
        if let deviceToken = installation["deviceToken"].stringValue {
            deviceTokens.append(deviceToken)
        }
    }

    return deviceTokens
}

drop.get("/:passId") { request in
    guard let passFileName = request.parameters["passId"]?.string,
        let vanityId = parseVanityId(from: passFileName),
        let pass = try findPassDocument(withVanityId: vanityId)
    else {
        return Response(status: .notFound)
    }

    guard case .binary(_, let data) = pass["data"], !data.isEmpty else {
        return Response(status: .noContent)
    }

    var headers: [HeaderKey: String] = ["Content-Type": "application/vnd.apple.pkpass"]
    if let updatedAt = pass["updatedAt"].dateValue {
        headers["Last-Modified"] = RFC1123.shared.formatter.string(from: updatedAt)
    }

    return Response(status: .ok, headers: headers, body: .data(data))
}

drop.post("/:passId") { request in
    guard validateMasterAuthorization(for: request) else {
        return Response(status: .unauthorized)
    }

    guard let passFileName = request.parameters["passId"]?.string,
        let vanityId = parseVanityId(from: passFileName)
    else {
        return Response(status: .badRequest)
    }

    if try findPassDocument(withVanityId: vanityId) != nil {
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

    let pass: Document = [
        "vanityId": ~vanityId,
        "authenticationToken": ~authenticationToken,
        "passTypeIdentifier": ~passTypeIdentifier,
        "serialNumber": ~serialNumber,
        "updatedAt": ~Date(),
        "data": BSON.Value.binary(subtype: .generic, data: bodyData),
    ]
    try passes.insert(pass)

    return Response(status: .created)
}

let network = APNSNetwork()

drop.put("/:passId") { request in
    guard validateMasterAuthorization(for: request) else {
        return Response(status: .unauthorized)
    }

    guard let passFileName = request.parameters["passId"]?.string,
        let vanityId = parseVanityId(from: passFileName)
    else {
        return Response(status: .badRequest)
    }

    guard var pass = try findPassDocument(withVanityId: vanityId) else {
        return Response(status: .notFound)
    }

    guard let bodyData = request.body.bytes, !bodyData.isEmpty else {
        return Response(status: .badRequest)
    }

    pass["data"] = BSON.Value.binary(subtype: .generic, data: bodyData)
    pass["updatedAt"] = ~Date()
    try passes.update(matching: "vanityId" == vanityId, to: pass)

    if let topic = pass["passTypeIdentifier"].stringValue {
        let certificatePath = drop.workDir + "certs.p12"
        let passphrase = "passcards"

        for deviceToken in try fetchDeviceTokens(for: pass["_id"]) {
            let message = ApplePushMessage(topic: topic, priority: 5, payload: ["aps": ""], deviceToken: deviceToken, certificatePath: certificatePath, passphrase: passphrase, sandbox: false, responseBlock: { response in
                print(response)
            }, networkError: { error in
                print(error)
            })
            _ = try network.sendPushWith(message: message)
        }
    }

    return Response(status: .ok)
}

drop.collection(WalletCollection(passes: passes, installations: installations))

drop.run()
