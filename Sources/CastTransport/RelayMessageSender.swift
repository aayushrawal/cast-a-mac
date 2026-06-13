import Foundation

final class RelayMessageSender: @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    private let maximumPendingMessages: Int
    private let lock = NSLock()
    private var pending: [URLSessionWebSocketTask.Message] = []
    private var isSending = false

    init(
        task: URLSessionWebSocketTask,
        maximumPendingMessages: Int
    ) {
        self.task = task
        self.maximumPendingMessages = maximumPendingMessages
    }

    func enqueue(_ message: URLSessionWebSocketTask.Message) {
        lock.lock()
        if pending.count >= maximumPendingMessages {
            pending.removeFirst()
        }
        pending.append(message)
        let shouldStart = !isSending
        if shouldStart {
            isSending = true
        }
        lock.unlock()

        if shouldStart {
            sendNext()
        }
    }

    private func sendNext() {
        lock.lock()
        guard !pending.isEmpty else {
            isSending = false
            lock.unlock()
            return
        }
        let message = pending.removeFirst()
        lock.unlock()

        Task { [weak self, task] in
            try? await task.send(message)
            self?.sendNext()
        }
    }
}
