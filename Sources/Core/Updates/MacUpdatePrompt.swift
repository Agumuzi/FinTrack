import SwiftUI
import AppKit
import Combine

/// One presentation bound to the main window; no independent update window.
@MainActor
final class MacUpdatePrompt: ObservableObject {
    static let shared = MacUpdatePrompt()
    enum Stage: String, Identifiable { case offer, downloading, ready; var id: String { rawValue } }
    @Published var stage: Stage?
    private var deferred: Stage?
    private var transfer: Task<Void, Never>?
    private var sheetObserver: AnyCancellable?
    private init() {
        sheetObserver = NotificationCenter.default.publisher(for: NSWindow.didEndSheetNotification).sink { [weak self] _ in
            Task { @MainActor in
                await Task.yield()
                guard let self, self.stage == nil, let next = self.deferred else { return }
                self.deferred = nil; self.show(next)
            }
        }
    }
    func show(_ next: Stage) {
        guard MacUpdateService.shared.release != nil else { return }
        if stage == nil && (MacApplicationRuntime.shared.mainWindow?.attachedSheet != nil || MacPermissionCoordinator.shared.presented) {
            deferred = next; return
        }
        MacApplicationRuntime.shared.showMain()
        stage = next
    }
    func dismiss() { stage = nil }
    func download() {
        guard !MacUpdateService.shared.busy else { return }
        stage = .downloading
        transfer = Task { await MacUpdateService.shared.downloadRelease(); transfer = nil }
    }
    func cancelDownload() { transfer?.cancel(); transfer = nil; dismiss() }
}

struct MacUpdateSheetPresenter: ViewModifier {
    @ObservedObject private var prompt = MacUpdatePrompt.shared
    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { prompt.stage != nil }, set: { if !$0 { prompt.dismiss() } })) {
            if let stage = prompt.stage {
                MacUpdatePromptView(stage:stage).id(stage).interactiveDismissDisabled()
            }
        }
    }
}

private struct MacUpdatePromptView: View {
    var stage: MacUpdatePrompt.Stage
    @ObservedObject private var updater = MacUpdateService.shared
    @State private var error: String?
    private var title: String { stage == .ready ? (updater.installing ? "正在安装更新" : "更新已就绪") : stage == .downloading ? "正在准备更新" : "发现新版本" }
    var body: some View {
        MacFormShell(width:560) {
            HStack(spacing:12) {
                MacSettingsIcon(symbol:stage == .ready ? "checkmark.circle.fill" : "arrow.down.circle",color:MacUI.accent,size:40)
                VStack(alignment:.leading,spacing:5) {
                    Text(title).appFont(.dialogTitle,weight:.semibold)
                    Text("FinTrack \(updater.release?.version ?? "")").appFont(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        } fields: {
            VStack(alignment:.leading,spacing:14) {
                if stage == .offer {
                    Text(updater.release?.notes ?? "").appFont(.body).textSelection(.enabled)
                        .padding(14).frame(maxWidth:.infinity,alignment:.leading).background(MacOverviewStyle.filters,in:RoundedRectangle(cornerRadius:10))
                    Text("下载并校验后，再由您确认安装。当前账本和设置将保留。").appFont(.caption).foregroundStyle(.secondary)
                } else if stage == .downloading {
                    if updater.busy { ProgressView().controlSize(.small).tint(MacUI.accent) }
                    Text(updater.status).appFont(.body).accessibilityIdentifier("updateDownloadStatus")
                } else {
                    Label(updater.installing ? "正在准备替换应用，请勿重复操作" : "安装包已下载并校验",systemImage:"checkmark.shield").appFont(.body,weight:.medium).foregroundStyle(.green)
                    Text("安装后会重新启动 FinTrack。您也可以稍后再安装，账本与设置会保留。").appFont(.body)
                    if updater.busy { ProgressView(); Text(updater.status).appFont(.caption).foregroundStyle(.secondary) }
                    if let message = updater.installError ?? error { Text(message).appFont(.caption).foregroundStyle(.red) }
                }
            }
        } footer: {
            HStack {
                if stage == .offer {
                    Button("取消",role:.cancel) { MacUpdatePrompt.shared.dismiss() }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("下载并安装") { MacUpdatePrompt.shared.download() }.buttonStyle(MacStandardButtonStyle(primary:true)).keyboardShortcut(.defaultAction).accessibilityIdentifier("downloadOfferedUpdate")
                } else if stage == .downloading {
                    Button(updater.busy ? "取消下载" : "关闭") { MacUpdatePrompt.shared.cancelDownload() }.keyboardShortcut(.cancelAction)
                    Spacer()
                    if !updater.busy && updater.archive == nil { Button("重试下载") { MacUpdatePrompt.shared.download() }.buttonStyle(MacStandardButtonStyle(primary:true)) }
                } else {
                    Button("稍后",role:.cancel) { MacUpdatePrompt.shared.dismiss() }.keyboardShortcut(.cancelAction).disabled(updater.busy)
                    Spacer()
                    Button("安装并重新启动") { Task { do { try await updater.installAndRelaunch() } catch { self.error = error.localizedDescription } } }
                        .buttonStyle(MacStandardButtonStyle(primary:true)).keyboardShortcut(.defaultAction).accessibilityIdentifier("confirmInstallUpdate").disabled(updater.busy)
                }
            }
        }.accessibilityElement(children:.contain)
    }
}
