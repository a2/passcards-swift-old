import Foundation
import MongoKitten
import Kitura

extension PasscardsServer {
    func makeVanityRouter() -> Router {
        let router = Router()
        router.all(middleware: BodyParser())
        router.get("/:passId", handler: getPass)
        router.post("/:passId", handler: uploadPass)
        router.put("/:passId", handler: updatePass)
        return router
    }

    func getPass(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        guard let passName = request.parameters["passId"],
            let vanityId = parseVanityId(from: passName),
            let pass = try passes.findOne(matching: "vanityId" == vanityId)
        else {
            try response.status(.notFound).end()
            return
        }

        guard case .binary(_, let data) = pass["data"], !data.isEmpty else {
            try response.status(.noContent).end()
            return
        }

        response.headers["Content-Type"] = "application/vnd.apple.pkpass"

        if let updatedAt = pass["updatedAt"].dateValue {
            response.headers["Last-Modified"] = rfc2616DateFormatter.string(from: updatedAt)
        }

        try response.send(data: Data(data)).end()
    }

    func isAuthorized(request: RouterRequest) -> Bool {
        return request.headers["Authorization"] == "Token \(updateToken)"
    }

    func uploadPass(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        guard isAuthorized(request: request) else {
            try response.status(.unauthorized).end()
            return
        }

        guard let passName = request.parameters["passId"],
            let vanityId = parseVanityId(from: passName)
        else {
            try response.status(.badRequest).end()
            return
        }

        guard try passes.findOne(matching: "vanityId" == vanityId) == nil else {
            response.headers["Location"] = request.url
            try response.status(.seeOther).end()
            return
        }

        guard case .some(.multipart(let parts)) = request.body else {
            try response.status(.badRequest).end()
            return
        }

        guard let authenticationToken = findString(in: parts, byName: "authenticationToken"),
            let passTypeIdentifier = findString(in: parts, byName: "passTypeIdentifier"),
            let serialNumber = findString(in: parts, byName: "serialNumber"),
            let bodyData = findData(in: parts, byName: "file")
        else {
            try response.status(.badRequest).end()
            return
        }

        var bodyBytes = [UInt8](repeating: 0, count: bodyData.count)
        _ = bodyBytes.withUnsafeMutableBufferPointer { bufferPtr in bodyData.copyBytes(to: bufferPtr) }

        let pass: Document = [
            "vanityId": ~vanityId,
            "authenticationToken": ~authenticationToken,
            "passTypeIdentifier": ~passTypeIdentifier,
            "serialNumber": ~serialNumber,
            "updatedAt": ~Date(),
            "data": BSON.Value.binary(subtype: .generic, data: bodyBytes),
        ]
        try passes.insert(pass)

        try response.status(.created).end()
    }

    func updatePass(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        guard isAuthorized(request: request) else {
            try response.status(.unauthorized).end()
            return
        }

        guard let passName = request.parameters["passId"],
            let vanityId = parseVanityId(from: passName)
        else {
            try response.status(.badRequest).end()
            return
        }

        guard var pass = try passes.findOne(matching: "vanityId" == vanityId) else {
            try response.status(.notFound).end()
            return
        }

        guard case .some(.multipart(let parts)) = request.body,
            let bodyData = findData(in: parts, byName: "file")
        else {
            try response.status(.badRequest).end()
            return
        }

        var bodyBytes = [UInt8](repeating: 0, count: bodyData.count)
        _ = bodyBytes.withUnsafeMutableBufferPointer { bufferPtr in bodyData.copyBytes(to: bufferPtr) }
        pass["data"] = .binary(subtype: .generic, data: bodyBytes)
        pass["updatedAt"] = ~Date()

        try passes.update(matching: "vanityId" == vanityId, to: pass)

        let payload = "{\"aps\":{}}".data(using: .utf8)!
        var notification = APNS.Notification(payload: payload)
        notification.topic = pass["passTypeIdentifier"].stringValue

        for installation in try installations.find(matching: "passId" == pass["_id"]) {
            let deviceToken = installation["deviceToken"].string
            apns.send(notification: notification, to: deviceToken)
        }

        try response.status(.OK).end()
    }
}
