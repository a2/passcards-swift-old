import Vapor
import Foundation

extension Date: NodeConvertible {
    public init(node: Node, in context: Context) throws {
        switch node {
        case .number(let number):
            switch number {
            case .double(let value):
                self = Date(timeIntervalSince1970: value)
            case .int(let value):
                self = Date(timeIntervalSince1970: TimeInterval(value))
            case .uint(let value):
                self = Date(timeIntervalSince1970: TimeInterval(value))
            }
        default:
            throw NodeError.unableToConvert(node: node, expected: "\(Date.self)")
        }
    }

    public func makeNode(context: Context) throws -> Node {
        return Node.number(.double(timeIntervalSince1970))
    }
}
