import Foundation

#if os(macOS)
let port: UInt16 = {
    guard let value = CommandLine.arguments.dropFirst().first,
          let port = UInt16(value) else {
        return 4_982
    }
    return port
}()

do {
    let host = try ScreenCaptureHost(port: port)
    print("Cast-a-mac LAN host starting on TCP port \(port).")
    print("macOS may ask for Screen Recording permission.")
    try await host.start()

    // Keep the command alive. The default SIGINT handler terminates it cleanly.
    while true {
        try await Task.sleep(for: .seconds(3_600))
    }
} catch {
    fputs("Host failed: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
#else
fputs("cast-host is a macOS-only executable. Run CastClient on iPadOS.\n", stderr)
exit(EXIT_FAILURE)
#endif
