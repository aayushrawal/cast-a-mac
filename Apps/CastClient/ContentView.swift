import SwiftUI

struct ContentView: View {
    @StateObject private var session = ClientSessionModel()

    var body: some View {
        Group {
            if case .connected(let name) = session.connectionState {
                RemoteDesktopView(
                    macName: name,
                    frame: session.latestFrame,
                    disconnect: session.disconnect,
                    movePointer: session.movePointer,
                    setPrimaryButton: session.setPrimaryButton,
                    click: session.click,
                    rightClick: session.rightClick,
                    scroll: session.scroll,
                    sendText: session.sendText,
                    sendKey: session.sendKey,
                    performThreeFingerSwipe: session.performThreeFingerSwipe
                )
            } else {
                NavigationSplitView {
                    MacListView(session: session)
                        .navigationTitle("Cast-a-mac")
                } detail: {
                    detail
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
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
        case .connected:
            EmptyView()
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
                ForEach(session.rememberedMacs) { mac in
                    Button {
                        session.connect(to: mac)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mac.name)
                                    .foregroundStyle(.primary)
                                Text(
                                    session.isNearby(mac)
                                        ? "Nearby · Local connection"
                                        : session.hasInternetAccess(mac)
                                            ? "Internet connection"
                                            : "Remembered · Link internet access"
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    session.isNearby(mac)
                                        || session.hasInternetAccess(mac)
                                        ? .green
                                        : .secondary
                                )
                            }
                        } icon: {
                            Image(systemName: "desktopcomputer")
                                .foregroundStyle(.blue)
                        }
                    }
                }

                Button {
                    session.showsLinkMac = true
                } label: {
                    Label("Link a Mac", systemImage: "link.badge.plus")
                }

                Text(session.internetStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .sheet(isPresented: $session.showsLinkMac) {
            LinkMacView(session: session)
        }
    }
}

private struct LinkMacView: View {
    @ObservedObject var session: ClientSessionModel
    @Environment(\.dismiss) private var dismiss
    @State private var relayURL = ""
    @State private var linkCode = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "https://relay.example.com",
                        text: $relayURL
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    TextField("8-character code", text: $linkCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("Internet Relay")
                } footer: {
                    Text(
                        "Use the relay URL and link code shown in the "
                            + "Cast-a-mac menu on your Mac."
                    )
                }

                if session.isLinkingMac {
                    ProgressView("Linking Mac...")
                }

                Text(session.internetStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Link a Mac")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Link") {
                        Task {
                            await session.linkMac(
                                relayURLText: relayURL,
                                code: linkCode
                            )
                        }
                    }
                    .disabled(
                        relayURL.isEmpty
                            || linkCode.isEmpty
                            || session.isLinkingMac
                    )
                }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
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
