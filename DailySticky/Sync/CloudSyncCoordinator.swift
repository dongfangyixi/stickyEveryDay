import CloudKit
import Foundation

@MainActor
final class CloudSyncCoordinator {
    var onStatusChange: ((CloudSyncStatus) -> Void)?
    var onResult: ((CloudSyncResult, CloudSyncSnapshot) throws -> Void)?

    private let service: CloudSyncServicing
    private let metadataStore: CloudSyncMetadataStore
    private var scheduledTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var pendingSnapshot: CloudSyncSnapshot?
    private var generation = 0

    init(service: CloudSyncServicing, metadataStore: CloudSyncMetadataStore) {
        self.service = service
        self.metadataStore = metadataStore
    }

    func schedule(snapshot: CloudSyncSnapshot) {
        scheduledTask?.cancel()
        let generation = generation
        scheduledTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled, let self, generation == self.generation else {
                return
            }
            self.start(snapshot: snapshot)
        }
    }

    func synchronizeNow(snapshot: CloudSyncSnapshot) {
        scheduledTask?.cancel()
        start(snapshot: snapshot)
    }

    func disable() {
        generation += 1
        scheduledTask?.cancel()
        syncTask?.cancel()
        scheduledTask = nil
        syncTask = nil
        pendingSnapshot = nil
        onStatusChange?(.localOnly)
    }

    private func start(snapshot: CloudSyncSnapshot) {
        if syncTask != nil {
            pendingSnapshot = snapshot
            return
        }

        let generation = generation
        let metadata = metadataStore.load()

        syncTask = Task { [weak self] in
            guard let self else {
                return
            }

            self.onStatusChange?(.checkingAccount)
            let availability = await self.service.accountAvailability()
            guard !Task.isCancelled, generation == self.generation else {
                return
            }
            if availability == .capabilityUnavailable {
                self.onStatusChange?(.capabilityUnavailable)
                self.finishSync(generation: generation)
                return
            }
            guard availability == .available else {
                self.onStatusChange?(.accountUnavailable)
                self.finishSync(generation: generation)
                return
            }

            self.onStatusChange?(.syncing)
            do {
                let result = try await self.service.synchronize(
                    localSnapshot: snapshot,
                    metadata: metadata
                )
                guard !Task.isCancelled, generation == self.generation else {
                    return
                }
                try self.onResult?(result, snapshot)
                try self.metadataStore.save(result.metadata)
                self.onStatusChange?(.upToDate(result.synchronizedAt))
                self.finishSync(generation: generation)
            } catch {
                guard !Task.isCancelled, generation == self.generation else {
                    return
                }
                self.onStatusChange?(Self.status(for: error))
                self.finishSync(generation: generation)
            }
        }
    }

    private func finishSync(generation: Int) {
        guard generation == self.generation else {
            return
        }

        syncTask = nil
        guard let pendingSnapshot else {
            return
        }
        self.pendingSnapshot = nil
        start(snapshot: pendingSnapshot)
    }

    private static func status(for error: Error) -> CloudSyncStatus {
        guard let cloudError = error as? CKError else {
            if case CloudSyncServiceError.accountUnavailable = error {
                return .accountUnavailable
            }
            return .failed(error.localizedDescription)
        }

        switch cloudError.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable,
             .requestRateLimited, .zoneBusy:
            return .offline
        case .notAuthenticated, .accountTemporarilyUnavailable:
            return .accountUnavailable
        default:
            return .failed(cloudError.localizedDescription)
        }
    }
}
