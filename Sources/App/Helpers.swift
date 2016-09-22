import Foundation
import MongoKitten

let rfc2616DateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss 'GMT'"
    dateFormatter.locale = Locale(identifier: "en_US")
    dateFormatter.timeZone = TimeZone(abbreviation: "GMT")
    return dateFormatter
}()

let iso8601DateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    return dateFormatter
}()


func makeId(length: Int = 10) -> String {
    var result = ""
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

func parseVanityId(from fileName: String) -> String? {
    guard fileName.lowercased().hasSuffix(".pkpass"),
        let extensionIndex = fileName.characters.index(of: "."),
        fileName[extensionIndex ..< fileName.endIndex].lowercased() == ".pkpass"
    else {
        return nil
    }

    return fileName[fileName.startIndex ..< extensionIndex]
}

func findPass(withVanityId vanityId: String) throws -> Document? {
    return try passes.findOne(matching: "vanityId" == vanityId)
}
