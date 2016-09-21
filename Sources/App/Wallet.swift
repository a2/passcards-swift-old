import Foundation
import MongoKitten
import Kitura
import KituraNet
import LoggerAPI

func makeWalletRouter() -> Router {
    let router = Router()
    router.all(middleware: BodyParser())
    router.post("/v1/devices/:deviceLibraryIdentifier/registrations/:passTypeIdentifier/:serialNumber", handler: registerDevice)
    router.get("/v1/devices/:deviceLibraryIdentifier/registrations/:passTypeIdentifier", handler: getSerialNumbers)
    router.get("/v1/passes/:passTypeIdentifier/:serialNumber", handler: getPassLatestVersion)
    router.delete("/v1/devices/:deviceLibraryIdentifier/registrations/:passTypeIdentifier/:serialNumber", handler: unregisterDevice)
    router.post("/v1/log", handler: logMessages)
    return router
}

private func registerDevice(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
    guard let deviceLibraryIdentifier = request.parameters["deviceLibraryIdentifier"],
        let passTypeIdentifier = request.parameters["passTypeIdentifier"],
        let serialNumber = request.parameters["serialNumber"]
    else {
        try response.status(.badRequest).end()
        return
    }

    guard case .some(.json(let json)) = request.body,
        let pushToken = json["pushToken"].string
    else {
        try response.status(.badRequest).end()
        return
    }

    let pass: Document
    do {
        let query: Query = "passTypeIdentifier" == passTypeIdentifier && "serialNumber" == serialNumber
        let localPass = try passes.findOne(matching: query)

        if let localPass = localPass {
            pass = localPass
        } else {
            try response.status(.notFound).end()
            return
        }
    }

    guard let authorization = request.headers["Authorization"],
        let authenticationToken = pass["authenticationToken"].stringValue,
        authorization == "ApplePass \(authenticationToken)"
    else {
        try response.status(.unauthorized).end()
        return
    }

    let query: Query = "deviceLibraryIdentifier" == deviceLibraryIdentifier && "passId" == pass["_id"]
    let created: Bool
    var installation: Document

    if let localInstallation = try installations.findOne(matching: query) {
        created = false
        installation = localInstallation
    } else {
        created = true
        installation = [
            "deviceLibraryIdentifier": ~deviceLibraryIdentifier,
            "passId": ~pass["_id"],
        ]
    }

    installation["deviceToken"] = ~pushToken

    if created {
        try installations.insert(installation)
        try response.status(.created).end()
    } else {
        try installations.update(matching: query, to: installation)
        try response.status(.OK).end()
    }
}

private func getSerialNumbers(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
    guard let deviceLibraryIdentifier = request.parameters["deviceLibraryIdentifier"],
        let passTypeIdentifier = request.parameters["passTypeIdentifier"]
    else {
        try response.status(.badRequest).end()
        return
    }

    let passParameters: Document
    if let passesUpdatedSinceString = request.queryParameters["passesUpdatedSince"], let passesUpdatedSince = iso8601DateFormatter.date(from: passesUpdatedSinceString) {
        passParameters = [
            "passes.passTypeIdentifier": ~passTypeIdentifier,
            "passes.updatedAt": ["$gte": ~passesUpdatedSince],
        ]
    } else {
        passParameters = [
            "passes.passTypeIdentifier": ~passTypeIdentifier
        ]
    }

    let cursor = try installations.aggregate(pipeline: [
        [
            "$match": ["deviceLibraryIdentifier": ~deviceLibraryIdentifier],
        ],
        [
            "$lookup": [
                "from": ~passes.name,
                "localField": "passId",
                "foreignField": "_id",
                "as": "passes",
            ],
        ],
        [
            "$match": ~passParameters,
        ],
    ])

    var serialNumbers = [String]()
    var lastUpdated: Date?

    for installation in cursor {
        if let pass = installation["passes"].document.arrayValue.first {
            serialNumbers.append(pass["serialNumber"].string)

            if let updatedAt = pass["updatedAt"].dateValue {
                switch lastUpdated {
                case .some(let value) where value < updatedAt:
                    lastUpdated = updatedAt
                case .none:
                    lastUpdated = updatedAt
                default:
                    break
                }
            }
        }
    }

    guard !serialNumbers.isEmpty else {
        try response.status(.noContent).end()
        return
    }

    try response
        .send(json: [
            "lastUpdated": iso8601DateFormatter.string(from: lastUpdated ?? Date()),
            "serialNumbers": serialNumbers
        ])
        .end()
}

private func getPassLatestVersion(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
    guard let passTypeIdentifier = request.parameters["passTypeIdentifier"],
        let serialNumber = request.parameters["serialNumber"]
    else {
        try response.status(.badRequest).end()
        return
    }

    let pass: Document
    do {
        let query: Query = "passTypeIdentifier" == passTypeIdentifier && "serialNumber" == serialNumber
        let localPass = try passes.findOne(matching: query)

        if let localPass = localPass {
            pass = localPass
        } else {
            try response.status(.notFound).end()
            return
        }
    }

    guard let authorization = request.headers["Authorization"],
        let authenticationToken = pass["authenticationToken"].stringValue,
        authorization == "ApplePass \(authenticationToken)"
    else {
        try response.status(.unauthorized).end()
        return
    }

    let updatedAt = pass["updatedAt"].dateValue ?? Date()
    if let ifModifiedSinceString = request.headers["If-Modified-Since"],
        let ifModifiedSince = rfc1123DateFormatter.date(from: ifModifiedSinceString),
        updatedAt.timeIntervalSince(ifModifiedSince) < 1 {

        try response.status(.notModified).end()
        return
    }

    response.headers["Content-Type"] = "application/vnd.apple.pkpass"
    response.headers["Last-Modified"] = rfc1123DateFormatter.string(from: updatedAt)

    if case .binary(_, let bytes) = pass["data"], !bytes.isEmpty {
        try response.send(data: Data(bytes)).end()
    } else {
        try response.status(.noContent).end()
    }
}

private func unregisterDevice(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
    guard let deviceLibraryIdentifier = request.parameters["deviceLibraryIdentifier"],
        let passTypeIdentifier = request.parameters["passTypeIdentifier"],
        let serialNumber = request.parameters["serialNumber"]
    else {
        try response.status(.badRequest).end()
        return
    }

    let pass: Document
    do {
        let query: Query = "passTypeIdentifier" == passTypeIdentifier && "serialNumber" == serialNumber
        let localPass = try passes.findOne(matching: query)

        if let localPass = localPass {
            pass = localPass
        } else {
            try response.status(.notFound).end()
            return
        }
    }

    guard let authorization = request.headers["Authorization"],
        let authenticationToken = pass["authenticationToken"].stringValue,
        authorization == "ApplePass \(authenticationToken)"
    else {
        try response.status(.unauthorized).end()
        return
    }

    let query: Query = "deviceLibraryIdentifier" == deviceLibraryIdentifier && "passId" == pass["_id"]

    if try installations.findOne(matching: query) != nil {
        try installations.remove(matching: query)
        try response.status(.OK).end()
    } else {
        try response.status(.notFound).end()
    }
}

private func logMessages(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
    guard case .some(.json(let json)) = request.body,
        let logs = json["logs"].arrayObject as? [String]
    else {
        try response.status(.badRequest).end()
        return
    }

    for log in logs {
        Log.verbose(log)
    }

    try response.status(.OK).end()
}
