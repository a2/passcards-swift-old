import Vapor
import Foundation
import Routing
import HTTP
import MongoKitten

class WalletCollection: RouteCollection {
    typealias Wrapped = HTTP.Responder

    static let iso8601DateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return dateFormatter
    }()

    let passes: MongoKitten.Collection
    let installations: MongoKitten.Collection

    init(passes: MongoKitten.Collection, installations: MongoKitten.Collection) {
        self.passes = passes
        self.installations = installations
    }

    func addRegisterDevice<Builder: RouteBuilder>(to builder: Builder) where Builder.Value == Wrapped {
        builder.add(.post, "v1", "devices", ":deviceLibraryIdentifier", "registrations", ":passTypeIdentifier", ":serialNumber") { request in
            guard let deviceLibraryIdentifier = request.parameters["deviceLibraryIdentifier"]?.string,
                let passTypeIdentifier = request.parameters["passTypeIdentifier"]?.string,
                let serialNumber = request.parameters["serialNumber"]?.string
            else {
                throw TypeSafeRoutingError.missingParameter
            }

            guard let pushToken = request.json?["pushToken"]?.string else {
                return Response(status: .badRequest)
            }

            let pass: Document
            do {
                let query: Query = "passTypeIdentifier" == passTypeIdentifier && "serialNumber" == serialNumber
                let localPass = try self.passes.findOne(matching: query)

                if let localPass = localPass {
                    pass = localPass
                } else {
                    return Response(status: .notFound)
                }
            }

            guard let authorization = request.headers["Authorization"],
                let authenticationToken = pass["authenticationToken"].stringValue,
                authorization == "ApplePass \(authenticationToken)"
            else {
                return Response(status: .unauthorized)
            }

            let query: Query = "deviceLibraryIdentifier" == deviceLibraryIdentifier && "passId" == pass["_id"]
            let created: Bool
            var installation: Document

            if let localInstallation = try self.installations.findOne(matching: query) {
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
                try self.installations.insert(installation)
                return Response(status: .created)
            } else {
                try self.installations.update(matching: query, to: installation)
                return Response(status: .ok)
            }
        }
    }

    func addGetSerialNumbers<Builder: RouteBuilder>(to builder: Builder) where Builder.Value == Wrapped {
        builder.add(.get, "v1", "devices", ":deviceLibraryIdentifier", "registrations", ":passTypeIdentifier") { request in
            guard let deviceLibraryIdentifier = request.parameters["deviceLibraryIdentifier"]?.string,
                let passTypeIdentifier = request.parameters["passTypeIdentifier"]?.string
            else {
                throw TypeSafeRoutingError.missingParameter
            }

            var passParameters: Document = ["passes.passTypeIdentifier": ~passTypeIdentifier]
            if let passesUpdatedSinceString = request.parameters["passesUpdatedSince"]?.string, let passesUpdatedSince = WalletCollection.iso8601DateFormatter.date(from: passesUpdatedSinceString) {
                passParameters["passes.updatedAt"] = ~passesUpdatedSince
            }

            let cursor = try self.installations.aggregate(pipeline: [
                [
                    "$match": ["deviceLibraryIdentifier": ~deviceLibraryIdentifier],
                ],
                [
                    "$lookup": [
                        "from": ~self.passes.name,
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

            if serialNumbers.isEmpty {
                return Response(status: .noContent)
            }

            return try Response(status: .ok, json: JSON([
                "lastUpdated": Node(WalletCollection.iso8601DateFormatter.string(from: lastUpdated ?? Date())),
                "serialNumbers": Node(serialNumbers.map { Node($0) }),
            ]))
        }
    }

    func addGetPassLatestVersion<Builder: RouteBuilder>(to builder: Builder) where Builder.Value == Wrapped {
        builder.add(.get, "v1", "passes", ":passTypeIdentifier", ":serialNumber") { request in
            guard let passTypeIdentifier = request.parameters["passTypeIdentifier"]?.string,
                let serialNumber = request.parameters["serialNumber"]?.string
            else {
                throw TypeSafeRoutingError.missingParameter
            }

            let pass: Document
            do {
                let query: Query = "passTypeIdentifier" == passTypeIdentifier && "serialNumber" == serialNumber
                let localPass = try self.passes.findOne(matching: query)

                if let localPass = localPass {
                    pass = localPass
                } else {
                    return Response(status: .notFound)
                }
            }

            guard let authorization = request.headers["Authorization"],
                let authenticationToken = pass["authenticationToken"].stringValue,
                authorization == "ApplePass \(authenticationToken)"
            else {
                return Response(status: .unauthorized)
            }

            let updatedAt = pass["updatedAt"].dateValue ?? Date()
            if let ifModifiedSinceString = request.headers["If-Modified-Since"]?.string,
                let ifModifiedSince = RFC1123.shared.formatter.date(from: ifModifiedSinceString),
                updatedAt.timeIntervalSince(ifModifiedSince) < 1 {

                return Response(status: .notModified)
            }

            let body: Body
            let status: Status

            if case .binary(_, let data) = pass["data"], !data.isEmpty {
                body = .data(data)
                status = .ok
            } else {
                body = .data([])
                status = .noContent
            }

            let headers: [HeaderKey: String] = [
                "Last-Modified": RFC1123.shared.formatter.string(from: updatedAt),
                "Content-Type": "application/vnd.apple.pkpass",
            ]
            return Response(status: status, headers: headers, body: body)
        }
    }

    func addUnregisterDevice<Builder: RouteBuilder>(to builder: Builder) where Builder.Value == Wrapped {
        builder.add(.delete, "v1", "devices", ":deviceLibraryIdentifier", "registrations", ":passTypeIdentifier", ":serialNumber") { request in
            guard let deviceLibraryIdentifier = request.parameters["deviceLibraryIdentifier"]?.string,
                let passTypeIdentifier = request.parameters["passTypeIdentifier"]?.string,
                let serialNumber = request.parameters["serialNumber"]?.string
            else {
                throw TypeSafeRoutingError.missingParameter
            }

            let pass: Document
            do {
                let query: Query = "passTypeIdentifier" == passTypeIdentifier && "serialNumber" == serialNumber
                let localPass = try self.passes.findOne(matching: query)

                if let localPass = localPass {
                    pass = localPass
                } else {
                    return Response(status: .notFound)
                }
            }

            guard let authorization = request.headers["Authorization"],
                let authenticationToken = pass["authenticationToken"].stringValue,
                authorization == "ApplePass \(authenticationToken)"
            else {
                return Response(status: .unauthorized)
            }

            let query: Query = "deviceLibraryIdentifier" == deviceLibraryIdentifier && "passId" == pass["_id"]

            if try self.installations.findOne(matching: query) != nil {
                try self.installations.remove(matching: query)
                return Response(status: .ok)
            } else {
                return Response(status: .notFound)
            }
        }
    }

    func addLog<Builder: RouteBuilder>(to builder: Builder) where Builder.Value == Wrapped {
        builder.add(.post, "v1", "log") { request in
            guard let logs = request.json?["logs"]?.array else {
                return Response(status: .badRequest)
            }

            for log in logs {
                if let string = log.string {
                    print(string)
                }
            }

            return Response(status: .ok)
        }
    }

    func build<Builder: RouteBuilder>(_ builder: Builder) where Builder.Value == Wrapped {
        addRegisterDevice(to: builder)
        addGetSerialNumbers(to: builder)
        addGetPassLatestVersion(to: builder)
        addUnregisterDevice(to: builder)
        addLog(to: builder)
    }
}
