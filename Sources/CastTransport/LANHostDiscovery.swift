import Foundation
import Network

public struct LANDiscoveredHost: Identifiable, Hashable, @unchecked Sendable {
    public let id: String
    public let name: String
    public let endpoint: NWEndpoint

    public init(name: String, endpoint: NWEndpoint) {
        self.id = String(describing: endpoint)
        self.name = name
        self.endpoint = endpoint
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public final class LANHostDiscovery: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.castamac.host-discovery")
    private let browser: NWBrowser

    public var onHostsChanged: (@Sendable ([LANDiscoveredHost]) -> Void)?
    public var onStateChange: (@Sendable (String) -> Void)?

    public init() {
        browser = NWBrowser(
            for: .bonjour(type: "_castamac._tcp", domain: nil),
            using: .tcp
        )
    }

    public func start() {
        browser.stateUpdateHandler = { [weak self] state in
            self?.onStateChange?("discovery: \(state)")
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let hosts = results.compactMap(Self.host(from:)).sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            self?.onHostsChanged?(hosts)
        }
        browser.start(queue: queue)
    }

    public func stop() {
        browser.cancel()
    }

    private static func host(from result: NWBrowser.Result) -> LANDiscoveredHost? {
        guard case let .service(name, _, _, _) = result.endpoint else {
            return nil
        }
        return LANDiscoveredHost(name: name, endpoint: result.endpoint)
    }
}
