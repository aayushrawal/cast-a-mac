import Foundation

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

    let signals = AsyncStream<Void> { continuation in
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT)
        source.setEventHandler {
            continuation.yield()
            continuation.finish()
        }
        source.resume()
        continuation.onTermination = { _ in source.cancel() }
    }
    for await _ in signals {
        break
    }
    try await host.stop()
} catch {
    fputs("Host failed: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
