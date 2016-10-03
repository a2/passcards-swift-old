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

public class PasscardsServer {
    let shoveClient: ShoveClient
    let database: MongoKitten.Database
    let passes: MongoKitten.Collection
    let installations: MongoKitten.Collection
    let updateToken: String

    public private(set) lazy var vanityRouter: Router = self.makeVanityRouter()
    public private(set) lazy var walletRouter: Router = self.makeWalletRouter()

    public init(database: MongoKitten.Database, shoveClient: ShoveClient, updateToken: String, configuration: ServerConfiguration = ServerConfiguration()) {
        self.database = database
        self.passes = database[configuration.passesCollectionName]
        self.installations = database[configuration.installationsCollectionName]
        self.shoveClient = shoveClient
        self.updateToken = updateToken
    }
}
