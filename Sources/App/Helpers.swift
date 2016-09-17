import Foundation

func makeId(length: Int = 10) -> String {
    var result = "'"
    for _ in 0 ..< length {
        let value = arc4random_uniform(62)
        switch value {
        case 0 ..< 26:
            result += String(UnicodeScalar(0x41 + UInt8(value)))
        case 26 ..< 52:
            result += String(UnicodeScalar(0x61 + UInt8(value - 26)))
        case 52 ..< 62:
            result += String(UnicodeScalar(0x30 + UInt8(value - 52)))
        default:
            preconditionFailure()
        }
    }

    return result
}
