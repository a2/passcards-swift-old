import Foundation
import Kitura
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

func parseVanityId(from fileName: String) -> String? {
    guard fileName.lowercased().hasSuffix(".pkpass"),
        let extensionIndex = fileName.characters.index(of: "."),
        fileName[extensionIndex ..< fileName.endIndex].lowercased() == ".pkpass"
    else {
        return nil
    }

    return fileName[fileName.startIndex ..< extensionIndex]
}

func findValue(in parts: [Part], byName name: String) -> ParsedBody? {
    for part in parts {
        if part.name == name {
            return part.body
        }
    }

    return nil
}

func findString(in parts: [Part], byName name: String) -> String? {
    return findValue(in: parts, byName: name).flatMap { value in
        if case .text(let string) = value {
            return string
        } else {
            return nil
        }
    }
}

func findData(in parts: [Part], byName name: String) -> Data? {
    return findValue(in: parts, byName: name).flatMap { value in
        if case .raw(let data) = value {
            return data
        } else {
            return nil
        }
    }
}
