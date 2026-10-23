import SwiftUI

enum MacFXSourceSelection {
    static func options(current:String, includeAutomatic: Bool = false) -> [(String,String)] {
        var values = (includeAutomatic ? [("自动", "auto")] : []) + [("系统数据源","free")] + MacFXService.sources.filter(\.enabled).map { ("自定义 · " + $0.name,$0.id.uuidString) }
        if !values.contains(where:{$0.1 == current}) { values.append(("原自定义来源不可用",current)) }
        return values
    }
}

struct MacFXScenarioSourcePicker: View {
    enum Scenario { case accounting, menuBar }
    let scenario: Scenario
    @ObservedObject private var service = MacFXApplication.shared.monitor
    private var key: WritableKeyPath<MacFXConfiguration,String> { scenario == .accounting ? \.accountingSourcePolicy : \.sourcePolicy }
    var body: some View {
        MacSettingsRow(label:scenario == .accounting ? "记账汇率来源" : "菜单栏汇率来源") {
            MacSettingsMenu(selection:Binding(get:{service.configuration[keyPath:key]},set:{ value in MacFXApplication.shared.update { $0[keyPath:key] = value } }),options:MacFXSourceSelection.options(current:service.configuration[keyPath:key], includeAutomatic: scenario == .menuBar))
                .frame(width:280).accessibilityIdentifier(scenario == .accounting ? "fxAccountingSource" : "fxMenuSource")
        }
    }
}

struct MacFXSystemSourceCard: View {
    @State private var checking = false
    @State private var result: String?
    @State private var available = false
    var body: some View {
        MacSettingsCard(title:"系统数据源",icon:"globe",subtitle:"软件内置的免费汇率，无需填写API密钥。",action:AnyView(Text("内置 · 免费").appFont(.caption,weight:.medium).foregroundStyle(.secondary))) {
            Text("提供日级参考报价；记账与菜单栏可分别选择使用。").appFont(.body)
            HStack {
                if let result { Label(result,systemImage:available ? "checkmark.circle" : "exclamationmark.circle").appFont(.caption).foregroundStyle(available ? Color.green : .secondary).accessibilityIdentifier("fxSystemSourceResult") }
                Spacer(minLength:12)
                Button(checking ? "正在检测…" : "检测可用性") { Task { await check() } }.disabled(checking).accessibilityIdentifier("fxSystemSourceCheck")
            }
        }.accessibilityElement(children:.contain).accessibilityIdentifier("fxSystemSourceCard")
    }
    private func check() async {
        checking = true; defer { checking = false }
        if MacFXApplication.shared.transport.mock { available = false; result = "隔离演示环境，未进行联网检测"; return }
        do {
            let quote = try await MacFXApplication.shared.transport.systemQuote(pair:MacFXPair(base:"USD",quote:"CNY"))
            available = true; result = "可用 · " + MacFXDates.label(quote.quoteTime)
        } catch { available = false; result = "暂未连接，请检查网络后重试" }
    }
}
