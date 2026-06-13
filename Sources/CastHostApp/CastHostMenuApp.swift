#if os(macOS)
import AppKit
import CastCore
import CastHostKit
import SwiftUI

@main
struct CastHostMenuApp: App {
    @NSApplicationDelegateAdaptor(HostApplicationDelegate.self)
    private var applicationDelegate
    @StateObject private var controller = HostMenuController.shared

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                Label(controller.status, systemImage: controller.statusIcon)
                    .font(.headline)

                Divider()

                TextField("Relay URL", text: $controller.relayURLText)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("Link code: \(controller.linkCode)")
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Button("Copy") {
                        controller.copyLinkCode()
                    }
                }

                Button("Save Internet Settings & Restart") {
                    controller.saveRelaySettingsAndRestart()
                }
                .disabled(controller.isBusy)

                Divider()

                Button("Start Streaming") {
                    controller.start()
                }
                .disabled(controller.isRunning || controller.isBusy)

                Button("Restart Streaming") {
                    controller.restart()
                }
                .disabled(controller.isBusy)

                Button("Stop Streaming") {
                    controller.stop()
                }
                .disabled(!controller.isRunning || controller.isBusy)

                Divider()

                Button("Screen Recording Settings") {
                    controller.openPrivacySettings(anchor: "Privacy_ScreenCapture")
                }

                Button("Accessibility Settings") {
                    controller.openPrivacySettings(anchor: "Privacy_Accessibility")
                }

                Divider()

                Button("Quit Cast-a-mac") {
                    controller.stop()
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(8)
            .frame(minWidth: 240)
        } label: {
            Image(
                systemName: controller.isRunning
                    ? "display.and.arrow.down"
                    : "display"
            )
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
private final class HostApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        HostMenuController.shared.start()
    }
}

@MainActor
private final class HostMenuController: ObservableObject {
    static let shared = HostMenuController()

    @Published private(set) var status = "Stopped"
    @Published private(set) var isRunning = false
    @Published private(set) var isBusy = false
    @Published var relayURLText: String

    private var host: ScreenCaptureHost?
    private var operation: Task<Void, Never>?
    private let relayURLKey = "relayBaseURL"

    private init() {
        relayURLText = UserDefaults.standard.string(
            forKey: relayURLKey
        ) ?? ""
    }

    var linkCode: String {
        HostRelayCredentialStore.loadOrCreate().linkCode
    }

    var statusIcon: String {
        if isBusy { return "arrow.triangle.2.circlepath" }
        return isRunning ? "checkmark.circle.fill" : "stop.circle"
    }

    func start() {
        guard !isRunning, !isBusy else { return }
        operation?.cancel()
        operation = Task {
            isBusy = true
            status = "Starting..."
            defer { isBusy = false }

            do {
                let host = try makeHost()
                try await host.start()
                self.host = host
                isRunning = true
                status = relayConfiguration == nil
                    ? "Available on local network"
                    : "Available locally and over internet"
            } catch {
                host = nil
                isRunning = false
                status = error.localizedDescription
            }
        }
    }

    func stop() {
        operation?.cancel()
        operation = Task {
            isBusy = true
            defer { isBusy = false }
            do {
                try await host?.stop()
            } catch {
                status = error.localizedDescription
            }
            host = nil
            isRunning = false
            status = "Stopped"
        }
    }

    func restart() {
        operation?.cancel()
        operation = Task {
            isBusy = true
            status = "Restarting..."
            do {
                try await host?.stop()
                host = nil
                let replacement = try makeHost()
                try await replacement.start()
                host = replacement
                isRunning = true
                status = relayConfiguration == nil
                    ? "Available on local network"
                    : "Available locally and over internet"
            } catch {
                host = nil
                isRunning = false
                status = error.localizedDescription
            }
            isBusy = false
        }
    }

    func openPrivacySettings(anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func saveRelaySettingsAndRestart() {
        let trimmed = relayURLText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        relayURLText = trimmed
        UserDefaults.standard.set(trimmed, forKey: relayURLKey)
        restart()
    }

    func copyLinkCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            linkCode,
            forType: .string
        )
    }

    private var relayConfiguration: RelayHostConfiguration? {
        let trimmed = relayURLText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else {
            return nil
        }
        return HostRelayCredentialStore.configuration(baseURL: url)
    }

    private func makeHost() throws -> ScreenCaptureHost {
        try ScreenCaptureHost(
            port: 4_982,
            relayConfiguration: relayConfiguration
        )
    }
}
#endif
