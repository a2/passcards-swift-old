import Foundation
import Kitura
import KituraNet
import MongoKitten

public struct ServerConfiguration {
    public var passesCollectionName = "passes"
    public var installationsCollectionName = "installations"

    public init() {
    }
}

public class Server: ServerDelegate {
    let apns: APNS
    let database: MongoKitten.Database
    let passes: MongoKitten.Collection
    let installations: MongoKitten.Collection
    let updateToken: String

    public private(set) lazy var vanityRouter: Router = self.makeVanityRouter()
    public private(set) lazy var walletRouter: Router = self.makeWalletRouter()
    public var fallbackServerDelegate: ServerDelegate? = nil

    public init(database: MongoKitten.Database, apns: APNS, updateToken: String, configuration: ServerConfiguration = ServerConfiguration()) {
        self.database = database
        self.passes = database[configuration.passesCollectionName]
        self.installations = database[configuration.installationsCollectionName]
        self.apns = apns
        self.updateToken = updateToken
    }

    public convenience init?(serverURI: String, databaseName: String, apnsCertificateURL: URL, certificatePassphrase: String?, updateToken: String, configuration: ServerConfiguration = ServerConfiguration()) {
        guard let server = try? MongoKitten.Server(serverURI),
            let apns = APNS(certificateURL: apnsCertificateURL, passphrase: certificatePassphrase)
        else {
            return nil
        }
        
        self.init(database: server[databaseName], apns: apns, updateToken: updateToken, configuration: configuration)
    }

    public func handle(request: ServerRequest, response: ServerResponse) {
        if request.urlString.hasPrefix("/v1/") {
            walletRouter.handle(request: request, response: response)
        } else if request.urlString.range(of: ".pkpass", options: [.anchored, .backwards]) != nil {
            vanityRouter.handle(request: request, response: response)
        } else {
            fallbackServerDelegate?.handle(request: request, response: response)
        }
    }
}
