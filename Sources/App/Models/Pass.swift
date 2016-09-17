import Vapor
import Fluent
import Foundation

class Pass: Model {
    var id: Node?
    var vanityId: String
    var authenticationToken: String
    var passTypeIdentifier: String
    var serialNumber: String
    var updatedAt = Date()
    var data: [UInt8]

    init(vanityId: String = makeId(), authenticationToken: String, passTypeIdentifier: String, serialNumber: String, data: [UInt8]) {
        self.vanityId = vanityId
        self.authenticationToken = authenticationToken
        self.passTypeIdentifier = passTypeIdentifier
        self.serialNumber = serialNumber
        self.data = data
    }

    required init(node: Node, in context: Context) throws {
        self.id = try node.extract("id")
        self.vanityId = try node.extract("vanityId")
        self.authenticationToken = try node.extract("authenticationToken")
        self.passTypeIdentifier = try node.extract("passTypeIdentifier")
        self.serialNumber = try node.extract("serialNumber")
        self.updatedAt = try node.extract("updatedAt") { (subnode: TimeInterval) in
            return Date(timeIntervalSince1970: subnode)
        }
        self.data = try node.extract("data") { (subnode: Node) in
            if case .bytes(let data) = subnode {
                return data
            } else {
                throw NodeError.unableToConvert(node: subnode, expected: "\([UInt8].self)")
            }
        }
    }

    func makeNode(context: Context) throws -> Node {
        return Node.object([
            "id": id ?? .null,
            "vanityId": .string(vanityId),
            "authenticationToken": .string(authenticationToken),
            "passTypeIdentifier": .string(passTypeIdentifier),
            "serialNumber": .string(serialNumber),
            "updatedAt": try updatedAt.makeNode(),
            "data": .bytes(data),
        ])
    }

    static func prepare(_ database: Database) throws {
        //
    }

    static func revert(_ database: Database) throws {
        //
    }
}
