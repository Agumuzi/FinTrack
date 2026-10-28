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

    func retry() {
        guard case .failed = state else { return }
        failedContainer = nil; failedLease = nil
        state = .notLoaded
        load()
    }

    func quarantineRecovery() {
        if case .ready(let container,let lease)=state {failedContainer=container;failedLease=lease}
        state = .failed("操作恢复尚未完成，账本暂时停止编辑。请退出后重新打开应用；恢复记录与原文件均已保留。")
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
            state = .failed("检测到账本辅助文件，但主数据库缺失。请保留原目录并从完整备份恢复，未创建新账本。")
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
                recoveryMessage = "上次操作未完成，已恢复操作前的账本与设置。自动入账已暂停，请核对后再开启。"
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
            try MacLoanSchedule.pinExisting(in: container.mainContext)
            // Once per container open; imports and native restores repair inside their own transaction.
            try MacDataManagement.reconcileCategories(in: container.mainContext)
            state = .ready(container, lease)
            failedContainer = nil; failedLease = nil
        } catch { failedContainer?.mainContext.rollback();failedContainer?.mainContext.autosaveEnabled=false;state = .failed(String(describing: error)) }
    }
}

struct MacLedgerWorkspaceGate: View {
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
                    Text("账本暂时无法打开").appFont(.section, weight: .semibold).accessibilityIdentifier("ledgerUnavailable")
                    Text("原账本保持原样。可重试打开，或先保留文件再安排恢复；菜单栏汇率仍可使用。").appFont(.body, weight: .regular)
                    DisclosureGroup("查看错误详情") {
                        Text(error).appFont(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }.accessibilityIdentifier("ledgerFailureDetails")
                    HStack {
                        Button("重试打开账本") { access.retry() }.accessibilityIdentifier("retryLedger")
                        Button("安全恢复说明") { recoveryHelp.toggle() }.accessibilityIdentifier("ledgerRecoveryHelp")
                    }
                    if recoveryHelp { Text("先退出应用，保留原账本目录及 SQLite、WAL、SHM 文件的完整副本。不要删除原库或以空库覆盖。若重试仍失败，应在隔离副本验证恢复方案后再处理原库。").appFont(.body, weight: .regular).textSelection(.enabled) }
                    MacAppEntrySettingsCard()
                }.padding(20)
            case .unconfigured, .notLoaded:
                ProgressView("正在准备账本…").appFont(.body).frame(maxWidth:.infinity,maxHeight:.infinity)

            }
        }
        .overlay(alignment: .bottomTrailing) {
            if MacPreferences.isTesting && ProcessInfo.processInfo.environment["FINTRACK_PRODUCT_SCREENSHOTS"] != "1" {
                Text("containers=\(access.containerOpenCount);requests=\(MacFXApplication.shared.transport.networkRequestCount);revision=\(monitor.revision)")
                    .font(.system(size: 8)).accessibilityIdentifier("fxIsolationMetrics")
            }
        }
        .alert("账本已安全恢复", isPresented: Binding(get: { access.recoveryMessage != nil }, set: { if !$0 { access.recoveryMessage = nil } })) {
            Button("知道了") { access.recoveryMessage = nil }
        } message: { Text(access.recoveryMessage ?? "") }
        .defaultAppStorage(MacPreferences.defaults)
        .background(MacMenuBarWindowProbe { runtime.mainWindow = $0 })
        .onAppear { access.load(createIfMissing: true) }
    }
}
