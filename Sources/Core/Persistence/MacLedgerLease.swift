import Foundation
import Darwin

/// One FinTrack process per persistent ledger. All windows in that process
/// share the MainActor ModelContainer; posting services do not suspend between
/// validation and save. The OS releases the lease on normal exit or a crash.
/// Keep the lock file: deleting it would permit two different locked inodes.
final class MacLedgerLease {
    enum Failure: LocalizedError {
        case alreadyOpen, unavailable(Int32)
        var errorDescription: String? {
            switch self {
            case .alreadyOpen:
                "This ledger is already open in another FinTrack process. Close that copy, then reopen FinTrack."
            case .unavailable(let code):
                "The ledger could not be opened safely (error \(code)). No financial data was changed."
            }
        }
    }

    let lockURL: URL
    private let descriptor: Int32

    static func acquire(for store: URL) throws -> MacLedgerLease {
        let lock = store.standardizedFileURL.appendingPathExtension("fintrack-lock")
        try FileManager.default.createDirectory(at: lock.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let fd = Darwin.open(lock.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw Failure.unavailable(errno) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            Darwin.close(fd)
            if code == EWOULDBLOCK { throw Failure.alreadyOpen }
            throw Failure.unavailable(code)
        }
        return MacLedgerLease(lockURL: lock, descriptor: fd)
    }

    private init(lockURL: URL, descriptor: Int32) {
        self.lockURL = lockURL
        self.descriptor = descriptor
    }

    deinit { Darwin.close(descriptor) }
}
