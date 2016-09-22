import Foundation
import Kitura
import HeliumLogger
import Server

let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let certificateURL = URL(string: "certs.p12", relativeTo: cwd)!

guard let server = Server(serverURI: "mongodb://user1:pswd1@0.0.0.0:27017", databaseName: "test", apnsCertificateURL: certificateURL, certificatePassphrase: "passcards", updateToken: "passcards") else {
    print("Could not load server with the given MongoDB and APNS credentials")
    exit(1)
}

HeliumLogger.use()
Kitura.addHTTPServer(onPort: 8080, with: server)
Kitura.run()
