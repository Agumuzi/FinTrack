import SwiftUI
import AppKit

@MainActor
final class MacUpdatePrompt {
    static let shared = MacUpdatePrompt()
    private var window: NSWindow?
    private var transfer: Task<Void, Never>?
    enum Stage { case offer, downloading, ready }
    func show(_ stage: Stage) {
        guard MacUpdateService.shared.release != nil else { return }
        window?.close()
        let panel = NSPanel(contentRect:NSRect(x:0,y:0,width:480,height:340),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        panel.title = stage == .ready ? "安装更新" : "FinTrack 软件更新"
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: MacUpdatePromptView(stage:stage).defaultAppStorage(MacPreferences.defaults))
        panel.center(); panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); window = panel
    }
    func dismiss() { window?.close() }
    func download() {
        guard !MacUpdateService.shared.busy else { return }
        show(.downloading)
        transfer = Task { await MacUpdateService.shared.downloadRelease(); transfer = nil }
    }
    func cancelDownload() { transfer?.cancel(); transfer = nil; dismiss() }
}

private struct MacUpdatePromptView: View {
    var stage: MacUpdatePrompt.Stage
    @ObservedObject private var updater = MacUpdateService.shared
    @State private var error: String?
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Label(stage == .ready ? "更新已就绪" : "发现新版本 \(updater.release?.version ?? "")",systemImage:stage == .ready ? "checkmark.seal.fill" : "arrow.down.circle.fill").font(.title2)
            if stage == .offer {
                ScrollView { Text(updater.release?.notes ?? "").textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }.frame(maxHeight:160)
                Text("下载并校验后，您可以选择安装并重新启动或稍后安装。").font(.caption).foregroundStyle(.secondary)
                HStack { Button("取消",role:.cancel) { MacUpdatePrompt.shared.dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("下载并安装") { MacUpdatePrompt.shared.download() }.keyboardShortcut(.defaultAction) }
            } else if stage == .downloading {
                if updater.busy { ProgressView().controlSize(.small) }
                Text(updater.status).accessibilityIdentifier("updateDownloadStatus")
                HStack { Button(updater.busy ? "取消下载" : "关闭") { MacUpdatePrompt.shared.cancelDownload() }.keyboardShortcut(.cancelAction); Spacer(); if !updater.busy && updater.archive == nil { Button("重试下载") { MacUpdatePrompt.shared.download() } } }
            } else {
                Text("安装包已下载并校验。安装后将重新启动 FinTrack，账本与设置保留。")
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
                HStack { Button("稍后",role:.cancel) { MacUpdatePrompt.shared.dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("安装并重新启动") { do { try updater.installAndRelaunch() } catch { self.error = error.localizedDescription } }.keyboardShortcut(.defaultAction).accessibilityIdentifier("confirmInstallUpdate") }
            }
        }.padding(24).frame(width:480).fixedSize(horizontal:false,vertical:true)
    }
}
