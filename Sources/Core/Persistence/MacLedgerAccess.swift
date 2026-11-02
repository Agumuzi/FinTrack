import SwiftUI
import SwiftData
import AppKit

/// Owns exactly one financial container/lease. Query services do not receive it.
@MainActor
final class MacLedgerAccess: ObservableObject {
    static let shared = MacLedgerAccess()
    enum State { case notLoaded, unconfigured, ready(ModelContainer, MacLedgerLease?), failed(String) }
    @Published private(set) var state: State = .notLoaded
    @Published var recoveryMessage: String?
    private var failedContainer: ModelContainer?
    private var failedLease: MacLedgerLease?
    private var opening = false
    private(set) var containerOpenCount = 0
    var container: ModelContainer? { if case .ready(let c, _) = state { return c }; return nil }
    var canConfirmUpdateLaunch: Bool {
        switch state { case .ready, .unconfigured: true; case .notLoaded, .failed: false }
    }

    func retry() {
        guard case .failed = state else { return }
        failedContainer = nil; failedLease = nil
        state = .notLoaded
        load()
    }

    func quarantineRecovery() {
        if case .ready(let container,let lease)=state {failedContainer=container;failedLease=lease}
        state = .failed(L10n.text("mac.ledgerAccess.quarantineRecovery.dd8a45a520"))
    }
    func load(createIfMissing: Bool = false) {
        if case .ready = state { return }
        if case .failed = state { return }
        guard !opening else { return }; opening = true
        defer { opening = false }
        let env = ProcessInfo.processInfo.environment
        if MacPreferences.isTesting && env["FINTRACK_FX_ONLY"] == "1" && !createIfMissing { state = .unconfigured; return }
        let memory = env["FINTRACK_V12_UI_TEST"] == "1"
        let testPath = env["FINTRACK_V13_TEST_STORE_PATH"]
        if !memory,testPath == nil,MacTestStore.requiresExplicitIsolation(bundleURL:Bundle.main.bundleURL) {
            state = .failed(L10n.text("mac.ledgerAccess.load.9806df04fc"))
            return
        }
        let url: URL?
        if let testPath {
            guard MacTestStore.isIsolated(testPath) else { state = .failed("Invalid isolated test store. No personal ledger was opened."); return }
            url = URL(fileURLWithPath: testPath).standardizedFileURL.resolvingSymlinksInPath()
        } else if memory { url = nil }
        else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let store = support.appendingPathComponent("FinTrackMac", isDirectory: true).appendingPathComponent("FinTrack.sqlite")
            // First use opens the built-in empty ledger. Existing-store failures stay failed;
            // this path never removes, replaces, or retries with a different database.
            url = store
        }
        // Missing main file plus SQLite sidecars can be an incomplete recovery,
        // not a fresh installation. Preserve every byte and ask for recovery.
        if let url, !FileManager.default.fileExists(atPath:url.path),
           ["-wal", "-shm"].contains(where:{ FileManager.default.fileExists(atPath:url.path + $0) }) {
            state = .failed(L10n.text("mac.ledgerAccess.load.457479499e"))
            return
        }
        let schema = Schema([Account.self, Transaction.self, Category.self, Goal.self, FinancialProfile.self, RecurringTransaction.self, DepositRecord.self, LoanRule.self])
        let config = url.map { ModelConfiguration(schema: schema, url: $0, cloudKitDatabase: .none) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            let lease = config.isStoredInMemoryOnly ? nil : try MacLedgerLease.acquire(for: config.url)
            failedLease = lease
            let container = try ModelContainer(for: schema, configurations: [config]); containerOpenCount += 1
            // SwiftData registers application-launch callbacks for its main context.
            // Keep a failed-opening container alive until retry, rather than
            // leaving a launch callback referencing a released context.
            failedContainer = container
            if try MacRecoveryJournal.recoverIfNeeded(in: container.mainContext) {
                recoveryMessage = L10n.text("mac.ledgerAccess.load.ec6a0eb2e5")
            }
            #if FINTRACK_LOCAL_VALIDATION
            if memory || testPath != nil { try MacOverviewFixtures.seed(in: container.mainContext) }
            #endif
            if MacPreferences.isTesting && env["FINTRACK_QUICK_ENTRY_FIXTURE"] == "1" {
                let context = container.mainContext
                if try context.fetchCount(FetchDescriptor<FinTrackMac.Category>()) == 0 {
                    context.insert(FinTrackMac.Category(name:"菜单测试餐饮",type:TransactionType.expense.rawValue))
                    try context.save()
                }
            }
            // Legacy loans lack a contract timezone. Expose their explicit
            // date review without changing the contract during ledger open.
            // Once per container open; imports and native restores repair inside their own transaction.
            try MacDataManagement.reconcileCategories(in: container.mainContext)
            state = .ready(container, lease)
            failedContainer = nil; failedLease = nil
        } catch { failedContainer?.mainContext.rollback();failedContainer?.mainContext.autosaveEnabled=false;state = .failed(String(describing: error)) }
    }
}

struct MacLedgerWorkspaceGate: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    @ObservedObject private var access = MacLedgerAccess.shared
    @ObservedObject private var runtime = MacApplicationRuntime.shared
    @ObservedObject private var monitor = MacFXApplication.shared.monitor
    @State private var recoveryHelp = false
    var body: some View {
        Group {
            switch access.state {
            case .ready(let container, _):
                FinTrackMacRootView().modelContainer(container).environmentObject(FinTrackMacApp.workspace)
            case .failed(let error):
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("mac.ledgerAccess.body.d194149edc")).appFont(.section, weight: .semibold).accessibilityIdentifier("ledgerUnavailable")
                    Text(L10n.text("mac.ledgerAccess.body.93c121cbed")).appFont(.body, weight: .regular)
                    DisclosureGroup(L10n.text("mac.ledgerAccess.DisclosureGroup.f1a9a03304")) {
                        Text(error).appFont(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }.accessibilityIdentifier("ledgerFailureDetails")
                    HStack {
                        Button(L10n.text("mac.ledgerAccess.body.722b81afec")) { access.retry() }.accessibilityIdentifier("retryLedger")
                        Button(L10n.text("mac.ledgerAccess.body.9529ff30a7")) { recoveryHelp.toggle() }.accessibilityIdentifier("ledgerRecoveryHelp")
                    }
                    if recoveryHelp { Text(L10n.text("mac.ledgerAccess.body.05e8dd437b")).appFont(.body, weight: .regular).textSelection(.enabled) }
                    MacAppEntrySettingsCard()
                }.padding(20)
            case .unconfigured, .notLoaded:
                ProgressView(L10n.text("mac.ledgerAccess.ProgressView.fa72950b11")).appFont(.body).frame(maxWidth:.infinity,maxHeight:.infinity)

            }
        }
        .overlay(alignment: .bottomTrailing) {
            if MacPreferences.isTesting && ProcessInfo.processInfo.environment["FINTRACK_PRODUCT_SCREENSHOTS"] != "1" {
                Text("containers=\(access.containerOpenCount);requests=\(MacFXApplication.shared.transport.networkRequestCount);revision=\(monitor.revision)")
                    .font(.system(size: 8)).accessibilityIdentifier("fxIsolationMetrics")
            }
        }
        .alert(L10n.text("mac.ledgerAccess.body.67e10d3865"), isPresented: Binding(get: { access.recoveryMessage != nil }, set: { if !$0 { access.recoveryMessage = nil } })) {
            Button(L10n.text("mac.ledgerAccess.body.de32e20193")) { access.recoveryMessage = nil }
        } message: { Text(access.recoveryMessage ?? "") }
        .defaultAppStorage(MacPreferences.defaults)
        .background(MacMenuBarWindowProbe { runtime.mainWindow = $0 })
        .onAppear { access.load(createIfMissing: true) }
    }
}
