import CastCore
import Foundation

public struct HostRelayCredentials: Codable, Equatable, Sendable {
    public let hostSecret: String
    public let linkCode: String

    public init(hostSecret: String, linkCode: String) {
        self.hostSecret = hostSecret
        self.linkCode = linkCode
    }
}

public enum HostRelayCredentialStore {
    public static func loadOrCreate() -> HostRelayCredentials {
        let fileManager = FileManager.default
        let directory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cast-a-mac")
        let credentialsURL = directory
            .appendingPathComponent("relay-credentials.json")

        if let data = try? Data(contentsOf: credentialsURL),
           let credentials = try? JSONDecoder().decode(
               HostRelayCredentials.self,
               from: data
           ) {
            return credentials
        }

        let credentials = HostRelayCredentials(
            hostSecret: UUID().uuidString + UUID().uuidString,
            linkCode: String(
                UUID().uuidString
                    .replacingOccurrences(of: "-", with: "")
                    .prefix(8)
            )
        )
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(credentials)
            try data.write(to: credentialsURL, options: .atomic)
        } catch {
            fputs("Could not persist relay credentials: \(error)\n", stderr)
        }
        return credentials
    }

    public static func configuration(
        baseURL: URL
    ) -> RelayHostConfiguration {
        let identity = HostIdentityStore.loadOrCreate()
        let credentials = loadOrCreate()
        return RelayHostConfiguration(
            baseURL: baseURL,
            hostID: identity.id,
            hostName: identity.name,
            hostSecret: credentials.hostSecret,
            linkCode: credentials.linkCode
        )
    }
}
