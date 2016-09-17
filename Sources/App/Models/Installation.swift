import Vapor
import Fluent
import Foundation

class Installation: Model {
    var id: Node?
    var deviceLibraryIdentifier: String?
    var deviceToken: String?
    var passId: Node?

    init() {
    }

    required init(node: Node, in context: Context) throws {
        self.id = try node.extract("id")
        self.deviceLibraryIdentifier = try node.extract("deviceLibraryIdentifier")
        self.passId = try node.extract("passId")
        self.deviceToken = try node.extract("deviceToken")
    }

    func makeNode(context: Context) throws -> Node {
        return try Node(node: [
            "id": id,
            "deviceLibraryIdentifier": deviceLibraryIdentifier,
            "passId": passId,
            "deviceToken": deviceToken,
        ])
    }

    func pass() throws -> Parent<Pass> {
        return try parent(passId)
    }

    static func prepare(_ database: Database) throws {
        //
    }

    static func revert(_ database: Database) throws {
        //
    }
}
