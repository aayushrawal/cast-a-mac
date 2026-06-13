import CastCore
import Foundation

public enum HostIdentityStore {
    public static func loadOrCreate() -> HostIdentity {
        let fileManager = FileManager.default
        let directory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cast-a-mac")
        let identityURL = directory.appendingPathComponent("host-identity.json")

        if let data = try? Data(contentsOf: identityURL),
           let identity = try? JSONDecoder().decode(HostIdentity.self, from: data) {
            return identity
        }

        let identity = HostIdentity(
            id: UUID(),
            name: ProcessInfo.processInfo.hostName
        )
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(identity)
            try data.write(to: identityURL, options: .atomic)
        } catch {
            fputs("Could not persist host identity: \(error)\n", stderr)
        }
        return identity
    }
}
