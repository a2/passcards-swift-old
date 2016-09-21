import Foundation

private class APNSURLSessionDelegate: NSObject, URLSessionDelegate {
    let identity: SecIdentity

    init(identity: SecIdentity) {
        self.identity = identity
    }

    @objc func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess else {
            completionHandler(.useCredential, nil)
            return
        }

        let credentials = URLCredential(identity: identity, certificates: [certificate!], persistence: .forSession)
        completionHandler(.useCredential, credentials)
    }
}

class APNS {
    private let session: URLSession
    private let sessionDelegate: APNSURLSessionDelegate
    private var baseURL: URL

    init(identity: SecIdentity, options: Options = Options()) {
        self.baseURL = options.baseURL
        self.sessionDelegate = APNSURLSessionDelegate(identity: identity)
        self.session = URLSession(configuration: options.sessionConfiguration, delegate: self.sessionDelegate, delegateQueue: nil)
    }

    private class func identity(for certificateURL: URL, passphrase: String?) -> SecIdentity? {
        guard let data = try? Data(contentsOf: certificateURL) else {
            return nil
        }

        let importOptions: [AnyHashable: Any]
        if let passphrase = passphrase {
            importOptions = [kSecImportExportPassphrase as String: passphrase]
        } else {
            importOptions = [:]
        }

        var items: CFArray?
        guard SecPKCS12Import(data as CFData, importOptions as CFDictionary, &items) == errSecSuccess else {
            return nil
        }

        guard let dictionary = (items as? [Any])?.first as? [String: Any],
            let identity = dictionary[kSecImportItemIdentity as String]
        else {
            return nil
        }

        return (identity as! SecIdentity)
    }

    convenience init?(certificateURL: URL, passphrase: String?, options: Options = Options()) {
        guard let identity = APNS.identity(for: certificateURL, passphrase: passphrase) else {
            return nil
        }

        self.init(identity: identity, options: options)
    }

    @discardableResult
    func send(notification: Notification, to deviceToken: String, shouldBeginRequest: Bool = true, completionHandler: @escaping (Result<Response>) -> Void = { _ in }) -> URLSessionTask {
        let url = baseURL.appendingPathComponent(deviceToken)
        var request = URLRequest(url: url)
        request.httpBody = notification.payload
        request.httpMethod = "POST"

        if let topic = notification.topic {
            request.addValue(topic, forHTTPHeaderField: "apns-topic")
        }

        if let priority = notification.priority {
            request.addValue(String(priority.rawValue), forHTTPHeaderField: "apns-priority")
        }

        if let id = notification.id {
            request.addValue(id.uuidString, forHTTPHeaderField: "apns-id")
        }

        if let expirationDate = notification.expirationDate {
            request.addValue(String(Int(expirationDate.timeIntervalSince1970)), forHTTPHeaderField: "apns-expiration")
        }

        let task = session.dataTask(with: request) { data, response, error in
            if let data = data {
                let httpResponse = response as! HTTPURLResponse
                let apnsIdString = httpResponse.allHeaderFields["apns-id"] as! String
                let apnsId = UUID(uuidString: apnsIdString)!
                let status = Status(rawValue: httpResponse.statusCode)!

                let error: APNS.Error?
                let timestamp: Date?
                if let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    error = APNS.Error(rawValue: json["reason"] as! String)
                    timestamp = Date(timeIntervalSince1970: (json["timestamp"] as! NSNumber).doubleValue)
                } else {
                    error = nil
                    timestamp = nil
                }

                let response = Response(id: apnsId, status: status, apnsError: error, timestamp: timestamp)
                completionHandler { response }
            } else if let error = error {
                completionHandler { throw error }
            }
        }

        if shouldBeginRequest {
            task.resume()
        }

        return task
    }
}

extension APNS {
    typealias Result<T> = () throws -> T

    enum NotificationPriority {
        case normal, high

        var rawValue: Int {
            switch self {
            case .normal:
                return 5
            case .high:
                return 10
            }
        }
    }

    struct Notification {
        var payload: Data
        var priority: NotificationPriority?
        var id: UUID?
        var expirationDate: Date?
        var topic: String?

        init(payload: Data) {
            self.payload = payload
        }
    }

    struct Options {
        var sessionConfiguration: URLSessionConfiguration = .default
        var isDevelopment = false
        var shouldUseAlternatePort = false

        init() {
        }

        fileprivate var port: Int {
            return shouldUseAlternatePort ? 2197 : 443
        }

        fileprivate var baseURL: URL {
            if isDevelopment {
                return URL(string: "https://api.development.push.apple.com:\(port)/3/device/")!
            } else {
                return URL(string: "https://api.push.apple.com:\(port)/3/device/")!
            }
        }
    }

    struct Response {
        var id: UUID
        var status: Status
        var apnsError: APNS.Error?
        var timestamp: Date?
    }

    enum Status: Int, CustomStringConvertible {
        case success = 200
        case badRequest = 400
        case badCertitficate = 403
        case badMethod = 405
        case deviceTokenIsNoLongerActive = 410
        case badNotificationPayload = 413
        case serverReceivedTooManyRequests = 429
        case internalServerError = 500
        case serverShutingDownOrUnavailable = 503

        public var description: String {
            switch self {
            case .success: return "Success"
            case .badRequest: return "Bad request"
            case .badCertitficate: return "There was an error with the certificate."
            case .badMethod: return "The request used a bad :method value. Only POST requests are supported."
            case .deviceTokenIsNoLongerActive: return "The device token is no longer active for the topic."
            case .badNotificationPayload: return "The notification payload was too large."
            case .serverReceivedTooManyRequests: return "The server received too many requests for the same device token."
            case .internalServerError: return "Internal server error"
            case .serverShutingDownOrUnavailable: return "The server is shutting down and unavailable."
            }
        }
    }

    enum Error: String, Swift.Error, CustomStringConvertible {
        case payloadEmpty = "PayloadEmpty"
        case payloadTooLarge = "PayloadTooLarge"
        case badTopic = "BadTopic"
        case topicDisallowed = "TopicDisallowed"
        case badMessageId = "BadMessageId"
        case badExpirationDate = "BadExpirationDate"
        case badPriority = "BadPriority"
        case missingDeviceToken = "MissingDeviceToken"
        case badDeviceToken = "BadDeviceToken"
        case deviceTokenNotForTopic = "DeviceTokenNotForTopic"
        case unregistered = "Unregistered"
        case duplicateHeaders = "DuplicateHeaders"
        case badCertificateEnvironment = "BadCertificateEnvironment"
        case badCertificate = "BadCertificate"
        case forbidden = "Forbidden"
        case badPath = "BadPath"
        case methodNotAllowed = "MethodNotAllowed"
        case tooManyRequests = "TooManyRequests"
        case idleTimeout = "IdleTimeout"
        case shutdown = "Shutdown"
        case internalServerError = "InternalServerError"
        case serviceUnavailable = "ServiceUnavailable"
        case missingTopic = "MissingTopic"

        var description: String {
            switch self {
            case .payloadEmpty: return "The message payload was empty."
            case .payloadTooLarge: return "The message payload was too large. The maximum payload size is 4096 bytes."
            case .badTopic: return "The apns-topic was invalid."
            case .topicDisallowed: return "Pushing to this topic is not allowed."
            case .badMessageId: return "The apns-id value is bad."
            case .badExpirationDate: return "The apns-expiration value is bad."
            case .badPriority: return "The apns-priority value is bad."
            case .missingDeviceToken: return "The device token is not specified in the request :path. Verify that the :path header contains the device token."
            case .badDeviceToken: return "The specified device token was bad. Verify that the request contains a valid token and that the token matches the environment."
            case .deviceTokenNotForTopic: return "The device token does not match the specified topic."
            case .unregistered: return "The device token is inactive for the specified topic."
            case .duplicateHeaders: return "One or more headers were repeated."
            case .badCertificateEnvironment: return "The client certificate was for the wrong environment."
            case .badCertificate: return "The certificate was bad."
            case .forbidden: return "The specified action is not allowed."
            case .badPath: return "The request contained a bad :path value."
            case .methodNotAllowed: return "The specified :method was not POST."
            case .tooManyRequests: return "Too many requests were made consecutively to the same device token."
            case .idleTimeout: return "Idle time out."
            case .shutdown: return "The server is shutting down."
            case .internalServerError: return "An internal server error occurred."
            case .serviceUnavailable: return "The service is unavailable."
            case .missingTopic: return "The apns-topic header of the request was not specified and was required. The apns-topic header is mandatory when the client is connected using a certificate that supports multiple topics."
            }
        }
    }
}
