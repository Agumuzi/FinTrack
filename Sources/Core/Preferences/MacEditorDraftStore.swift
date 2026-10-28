import Foundation
import SwiftData

/// Session-only drafts never enter a backup or the financial store. Restoring
/// another ledger invalidates every draft so old inputs cannot overwrite it.
@MainActor final class MacEditorDraftStore {
    static let shared = MacEditorDraftStore()
    private var values: [String: Any] = [:]
    private var observer: NSObjectProtocol?
    private(set) var generation = 0
    private init() {
        observer = NotificationCenter.default.addObserver(forName: MacSettingsStore.restoreCompleted, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.values.removeAll(); self?.generation += 1 }
        }
    }
    static func key(_ kind: String, _ id: String, context: ModelContext) -> String { "\(ObjectIdentifier(context.container))/\(kind)/\(id)" }
    func load<T>(_ key: String, as type: T.Type) -> T? { values[key] as? T }
    func save<T>(_ value: T, key: String, generation: Int) { if generation == self.generation { values[key] = value } }
    func remove(_ key: String) { values[key] = nil }
}
