#if os(macOS)
import AppKit
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

    private var host: ScreenCaptureHost?
    private var operation: Task<Void, Never>?

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
                let host = try ScreenCaptureHost(port: 4_982)
                try await host.start()
                self.host = host
                isRunning = true
                status = "Streaming on port 4982"
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
                let replacement = try ScreenCaptureHost(port: 4_982)
                try await replacement.start()
                host = replacement
                isRunning = true
                status = "Streaming on port 4982"
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
}
#endif
