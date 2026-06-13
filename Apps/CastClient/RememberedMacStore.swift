import Foundation
import Security

struct RememberedMac: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var lastSeenAt: Date
    var relayBaseURL: URL?
    var relayAccessToken: String?
}

final class RememberedMacStore {
    private let defaults: UserDefaults
    private let key = "rememberedMacs.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [RememberedMac] {
        guard let data = defaults.data(forKey: key),
              let records = try? JSONDecoder().decode(
                  [RememberedMac].self,
                  from: data
              ) else {
            return []
        }
        return records.map { record in
            var record = record
            record.relayAccessToken = RelayTokenKeychain.load(
                hostID: record.id
            )
            return record
        }
    }

    func save(_ records: [RememberedMac]) {
        for record in records {
            if let token = record.relayAccessToken {
                RelayTokenKeychain.save(token, hostID: record.id)
            }
        }
        let recordsWithoutTokens = records.map { record in
            var record = record
            record.relayAccessToken = nil
            return record
        }
        guard let data = try? JSONEncoder().encode(recordsWithoutTokens) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}

private enum RelayTokenKeychain {
    private static let service = "com.castamac.client.relay"

    static func load(hostID: UUID) -> String? {
        var query = baseQuery(hostID: hostID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(
            query as CFDictionary,
            &result
        ) == errSecSuccess,
        let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String, hostID: UUID) {
        let query = baseQuery(hostID: hostID)
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func baseQuery(hostID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostID.uuidString
        ]
    }
}
