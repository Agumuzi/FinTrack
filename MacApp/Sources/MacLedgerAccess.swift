import SwiftUI
import SwiftData
import AppKit

/// Owns exactly one financial container/lease. Query services do not receive it.
@MainActor
final class MacLedgerAccess: ObservableObject {
    static let shared = MacLedgerAccess()
    enum State { case notLoaded, unconfigured, ready(ModelContainer, MacLedgerLease?), failed(String) }
    @Published private(set) var state: State = .notLoaded
    private var opening = false
    private(set) var containerOpenCount = 0
    var container: ModelContainer? { if case .ready(let c, _) = state { return c }; return nil }

    func load(createIfMissing: Bool = false) {
        if case .ready = state { return }
        if case .failed = state { return }
        guard !opening else { return }; opening = true
        defer { opening = false }
        let env = ProcessInfo.processInfo.environment
        if MacPreferences.isTesting && env["FINTRACK_FX_ONLY"] == "1" && !createIfMissing { state = .unconfigured; return }
        let memory = env["FINTRACK_V12_UI_TEST"] == "1"
        let testPath = env["FINTRACK_V13_TEST_STORE_PATH"]
        let url: URL?
        if let testPath {
            guard MacTestStore.isIsolated(testPath) else { state = .failed("Invalid isolated test store. No personal ledger was opened."); return }
            url = URL(fileURLWithPath: testPath).standardizedFileURL.resolvingSymlinksInPath()
        } else if memory { url = nil }
        else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let store = support.appendingPathComponent("FinTrackMac", isDirectory: true).appendingPathComponent("FinTrack.sqlite")
            guard createIfMissing || FileManager.default.fileExists(atPath: store.path) else { state = .unconfigured; return }
            url = store
        }
        let schema = Schema([Account.self, Transaction.self, Category.self, Goal.self, FinancialProfile.self, RecurringTransaction.self, DepositRecord.self, LoanRule.self])
        let config = url.map { ModelConfiguration(schema: schema, url: $0, cloudKitDatabase: .none) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            let lease = config.isStoredInMemoryOnly ? nil : try MacLedgerLease.acquire(for: config.url)
            let container = try ModelContainer(for: schema, configurations: [config]); containerOpenCount += 1
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
            state = .ready(container, lease)
        } catch { state = .failed(String(describing: error)) }
    }
}

struct MacLedgerWorkspaceGate: View {
    @ObservedObject private var access = MacLedgerAccess.shared
    @ObservedObject private var runtime = MacApplicationRuntime.shared
    @ObservedObject private var monitor = MacFXApplication.shared.monitor
    var body: some View {
        Group {
            switch access.state {
            case .ready(let container, _):
                FinTrackMacRootView().modelContainer(container).environmentObject(FinTrackMacApp.workspace)
            case .failed(let error):
                VStack(alignment: .leading, spacing: 12) {
                    Text("账本暂时无法打开").appFont(.section, weight: .semibold).accessibilityIdentifier("ledgerUnavailable")
                    Text("未用空账本替换原数据。汇率查询和换算仍可使用。").appFont(.body, weight: .regular)
                    Text(error).appFont(.caption, weight: .regular).textSelection(.enabled)
                    MacStandaloneFXWorkspace(runtime: runtime)
                }.padding(20)
            case .unconfigured, .notLoaded:
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("FinTrack").appFont(.pageTitle, weight: .bold)
                            Text("可以直接查询汇率与换算，也可以开始记账。").appFont(.body, weight: .regular).foregroundStyle(.secondary).accessibilityIdentifier("ledgerNotConfigured")
                        }
                        Spacer()
                        Button("开始记账") { access.load(createIfMissing: true) }.buttonStyle(MacSettingsButtonStyle(primary: true, height: 40)).accessibilityIdentifier("beginBookkeeping")
                    }
                    MacStandaloneFXWorkspace(runtime: runtime)
                }.padding(20)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if MacPreferences.isTesting {
                Text("containers=\(access.containerOpenCount);requests=\(MacFXApplication.shared.transport.networkRequestCount);revision=\(monitor.revision)")
                    .font(.system(size: 8)).accessibilityIdentifier("fxIsolationMetrics")
            }
        }
        .defaultAppStorage(MacPreferences.defaults)
        .background(MacMenuBarWindowProbe { runtime.mainWindow = $0 })
        .onAppear { access.load() }
    }
}
