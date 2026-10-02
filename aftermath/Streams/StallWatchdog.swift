import Foundation

/// One-shot timer used to flag streams that never start playing.
@MainActor
final class StallWatchdog {
    private var task: Task<Void, Never>?

    /// Replaces any pending timer.
    func arm(after seconds: Double, onTimeout: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            onTimeout()
        }
    }

    func disarm() {
        task?.cancel()
        task = nil
    }
}
