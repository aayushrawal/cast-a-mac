import SwiftUI

struct ContentView: View {
    @StateObject private var session = ClientSessionModel()

    var body: some View {
        NavigationSplitView {
            MacListView(session: session)
                .navigationTitle("Cast-a-mac")
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            session.startBrowsing()
        }
        .onDisappear {
            session.stopBrowsing()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch session.connectionState {
        case .connected(let name):
            RemoteDesktopView(
                macName: name,
                frame: session.latestFrame,
                disconnect: session.disconnect,
                movePointer: session.movePointer,
                setPrimaryButton: session.setPrimaryButton,
                click: session.click,
                rightClick: session.rightClick,
                scroll: session.scroll,
                sendText: session.sendText
            )
        case .connecting(let name):
            ConnectionProgressView(macName: name)
        case .failed(let message):
            ContentUnavailableView(
                "Connection Failed",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .browsing:
            WelcomeView()
        }
    }
}

private struct MacListView: View {
    @ObservedObject var session: ClientSessionModel

    var body: some View {
        List {
            Section("Nearby Macs") {
                if session.hosts.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Looking on your local network...")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(session.hosts) { host in
                        Button {
                            session.connect(to: host)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(host.name)
                                        .foregroundStyle(.primary)
                                    Text("Available nearby")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            } icon: {
                                Image(systemName: "desktopcomputer")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }

            Section("Your Macs") {
                Button {
                    session.showsInternetPreview.toggle()
                } label: {
                    Label("Sign in with Apple", systemImage: "person.crop.circle.badge.plus")
                }

                if session.showsInternetPreview {
                    Text(session.internetStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct WelcomeView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Choose a Mac", systemImage: "ipad.and.iphone")
        } description: {
            Text("Select an available Mac to begin a remote session.")
        } actions: {
            Text("The Mac host must be running on the same Wi-Fi network for now.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ConnectionProgressView: View {
    let macName: String

    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
            Text("Connecting to \(macName)")
                .font(.title2.weight(.semibold))
            Text("Establishing a low-latency video session...")
                .foregroundStyle(.secondary)
        }
    }
}
