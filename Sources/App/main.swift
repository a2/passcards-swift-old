import Foundation
import MongoKitten
import Kitura
import HeliumLogger

HeliumLogger.use()

let mongo: MongoKitten.Server
do {
    mongo = try Server("mongodb://user1:pswd1@0.0.0.0:27017", automatically: true)
} catch {
    print("MongoDB is not available on the given host and port")
    exit(1)
}

let database = mongo["test"]
let passes = database["passes"]
let installations = database["installations"]

let apns: APNS = {
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    if let certificateURL = URL(string: "certs.p12", relativeTo: cwd),
        let apns = APNS(certificateURL: certificateURL, passphrase: "passcards") {
        return apns
    } else {
        print("Error loading certificates from URL with given passphrase")
        exit(1)
    }
}()

let router = Router()
router.all("/passes", middleware: makeVanityRouter())
router.all("/wallet", middleware: makeWalletRouter())
router.all { request, response, next in
    next()
}

Kitura.addHTTPServer(onPort: 8080, with: router)
Kitura.run()
