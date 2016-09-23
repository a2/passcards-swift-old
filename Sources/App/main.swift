import Commander
import Foundation
import HeliumLogger
import Kitura
import MongoKitten
import Server

let databaseOption = Option("database", "mongodb://localhost:27017/passcards", flag: "d", description: "The MongoDB server and database (in valid connection string format).")
let certificatePath = Option("cert", "", flag: "c", description: "Path to the APNS certificate / private key in .p12 format.")
let passphrase = Option("passphrase", "", flag: "p", description: "Passphrase to decrypt the certificate file.")
let updateToken = Option("updateToken", "", flag: "u", description: "The authentication token to require for uploading or updating passes.")
let port = Option("port", 8080, flag: "p", description: "The port on which to run the server.")

enum AppError: Error {
    case invalidDatabaseURI
    case badDatabaseCredentials
    case missingCertificate
    case invalidAPNSCredentials
}

let main = command(databaseOption, certificatePath, passphrase, updateToken, port) { databaseURI, certificatePath, passphrase, updateToken, port in
    guard let databaseURL = URL(string: databaseURI) else {
        throw AppError.invalidDatabaseURI
    }

    let serverURL = databaseURL.deletingLastPathComponent()
    let database = databaseURL.lastPathComponent

    let server = try Server(serverURL as NSURL, automatically: false)

    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    guard let certificateURL = URL(string: certificatePath, relativeTo: cwd) else {
        throw AppError.missingCertificate
    }

    guard let apns = APNS(certificateURL: certificateURL, passphrase: (!passphrase.isEmpty ? passphrase : nil)) else {
        throw AppError.invalidAPNSCredentials
    }

    do {
        try server.connect()
    } catch {
        throw AppError.badDatabaseCredentials
    }

    let passcardsServer = PasscardsServer(database: server[database], apns: apns, updateToken: updateToken)

    HeliumLogger.use()
    Kitura.addHTTPServer(onPort: port, with: passcardsServer)
    Kitura.run()
}

main.run()
