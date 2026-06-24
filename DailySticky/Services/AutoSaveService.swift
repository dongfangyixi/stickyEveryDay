import Foundation

@MainActor
final class AutoSaveService {
    private var workItem: DispatchWorkItem?

    func schedule(after delay: TimeInterval = 0.45, _ action: @escaping @MainActor () -> Void) {
        workItem?.cancel()

        let item = DispatchWorkItem {
            Task { @MainActor in
                action()
            }
        }

        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}

