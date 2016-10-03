import Foundation
import Kitura
import KituraNet
import MongoKitten
import Shove

public struct ServerConfiguration {
    public var passesCollectionName = "passes"
    public var installationsCollectionName = "installations"

    public init() {
    }
}

public class PasscardsServer: ServerDelegate {
    let shoveClient: ShoveClient
    let database: MongoKitten.Database
    let passes: MongoKitten.Collection
    let installations: MongoKitten.Collection
    let updateToken: String

    public private(set) lazy var vanityRouter: Router = self.makeVanityRouter()
    public private(set) lazy var walletRouter: Router = self.makeWalletRouter()
    public var fallbackServerDelegate: ServerDelegate? = nil

    public init(database: MongoKitten.Database, shoveClient: ShoveClient, updateToken: String, configuration: ServerConfiguration = ServerConfiguration()) {
        self.database = database
        self.passes = database[configuration.passesCollectionName]
        self.installations = database[configuration.installationsCollectionName]
        self.shoveClient = shoveClient
        self.updateToken = updateToken
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
