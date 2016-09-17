import Vapor
import Foundation
import Routing
import HTTP

class WalletCollection: RouteCollection, EmptyInitializable {
    typealias Wrapped = HTTP.Responder

    static let iso8601DateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return dateFormatter
    }()

    required init() {
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

            let pass: Pass
            do {
                let localPass = try Pass.query()
                    .filter("passTypeIdentifier", passTypeIdentifier)
                    .filter("serialNumber", serialNumber)
                    .first()
                if let localPass = localPass {
                    pass = localPass
                } else {
                    return Response(status: .notFound)
                }
            }

            guard let authorization = request.headers["Authorization"], authorization == "ApplePass \(pass.authenticationToken)" else {
                return Response(status: .unauthorized)
            }

            let installation: Installation
            do {
                let localInstallation = try Installation.query()
                    .filter("deviceLibraryIdentifier", deviceLibraryIdentifier)
                    .filter("passId", pass.id!)
                    .first()
                if let localInstallation = localInstallation {
                    installation = localInstallation
                } else {
                    installation = Installation()
                    installation.passId = pass.id!
                    installation.deviceLibraryIdentifier = deviceLibraryIdentifier
                }
            }

            installation.deviceToken = pushToken

            let existed = installation.id != nil
            try installation.save()

            return Response(status: existed ? .noContent : .created)
        }
    }

    func addGetSerialNumbers<Builder: RouteBuilder>(to builder: Builder) where Builder.Value == Wrapped {
        builder.add(.get, "v1", "devices", ":deviceLibraryIdentifier", "registrations", ":passTypeIdentifier") { request in
            guard let deviceLibraryIdentifier = request.parameters["deviceLibraryIdentifier"]?.string,
                let passTypeIdentifier = request.parameters["passTypeIdentifier"]?.string
            else {
                throw TypeSafeRoutingError.missingParameter
            }

            var query = try Installation.query()
                .filter("deviceLibraryIdentifier", deviceLibraryIdentifier)
                .union(Pass.self, localKey: "passId")
                .filter(Pass.self, "passTypeIdentifier", passTypeIdentifier)

            if let passesUpdatedSinceString = request.parameters["passesUpdatedSince"]?.string, let passesUpdatedSince = WalletCollection.iso8601DateFormatter.date(from: passesUpdatedSinceString) {
                query = try query.filter(Pass.self, "updatedAt", passesUpdatedSince)
            }

            var serialNumbers = [String]()
            var lastUpdated: Date?

            for installation in try query.all() {
                if let pass = try installation.pass().get() {
                    serialNumbers.append(pass.serialNumber)

                    switch lastUpdated {
                    case .some(let value) where value < pass.updatedAt:
                        lastUpdated = pass.updatedAt
                    case .none:
                        lastUpdated = pass.updatedAt
                    default:
                        break
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

            let pass: Pass
            do {
                let localPass = try Pass.query()
                    .filter("passTypeIdentifier", passTypeIdentifier)
                    .filter("serialNumber", serialNumber)
                    .first()
                if let localPass = localPass {
                    pass = localPass
                } else {
                    return Response(status: .notFound)
                }
            }

            guard let authorization = request.headers["Authorization"], authorization == "ApplePass \(pass.authenticationToken)" else {
                return Response(status: .unauthorized)
            }

            if let ifModifiedSinceString = request.headers["If-Modified-Since"]?.string,
                let ifModifiedSince = RFC1123.shared.formatter.date(from: ifModifiedSinceString),
                pass.updatedAt.timeIntervalSince(ifModifiedSince) < 1 {

                return Response(status: .notModified)
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
    }

    func addUnregisterDevice<Builder: RouteBuilder>(to builder: Builder) where Builder.Value == Wrapped {
        builder.add(.delete, "v1", "devices", ":deviceLibraryIdentifier", "registrations", ":passTypeIdentifier", ":serialNumber") { request in
            guard let deviceLibraryIdentifier = request.parameters["deviceLibraryIdentifier"]?.string,
                let passTypeIdentifier = request.parameters["passTypeIdentifier"]?.string,
                let serialNumber = request.parameters["serialNumber"]?.string
            else {
                throw TypeSafeRoutingError.missingParameter
            }

            let pass: Pass
            do {
                let localPass = try Pass.query()
                    .filter("passTypeIdentifier", passTypeIdentifier)
                    .filter("serialNumber", serialNumber)
                    .first()
                if let localPass = localPass {
                    pass = localPass
                } else {
                    return Response(status: .notFound)
                }
            }

            guard let authorization = request.headers["Authorization"], authorization == "ApplePass \(pass.authenticationToken)" else {
                return Response(status: .unauthorized)
            }

            let installation: Installation
            do {
                let localInstallation = try Installation.query()
                    .filter("deviceLibraryIdentifier", deviceLibraryIdentifier)
                    .filter("passId", pass.id!)
                    .first()
                if let localInstallation = localInstallation {
                    installation = localInstallation
                } else {
                    return Response(status: .notFound)
                }
            }

            try installation.delete()

            return Response(status: .ok)
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
