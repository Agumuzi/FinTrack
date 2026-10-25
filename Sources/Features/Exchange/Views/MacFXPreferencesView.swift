import SwiftUI

struct MacFXReferenceField: View {
    @ObservedObject private var service = MacFXApplication.shared.monitor
    @State private var reference = "USD"
    @State private var custom = false
    @State private var error: String?
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Text("默认换算币种").appFont(.body).foregroundStyle(.secondary)
                Spacer(minLength:12)
                MacEditableCurrencyMenu(currency:Binding(get:{reference},set:{ value in reference = value; if !custom { apply() } }),custom:$custom,codes:MacFXCatalog.codes,identifier:"fxReferenceCurrency",textIdentifier:"fxReferenceCustom")
            }
            if custom {
                HStack {
                    Text("输入代码后应用").appFont(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("应用",action:apply).buttonStyle(MacSettingsButtonStyle(height:40))
                        .disabled((try? MacFXPair(base:reference,quote:reference)) == nil).accessibilityIdentifier("fxReferenceApply")
                }
            }
            if let error { Text(error).appFont(.caption).foregroundStyle(.red) }
        }.onAppear { reference = service.configuration.referenceCurrency }
            .onChange(of:service.configuration.referenceCurrency) { _,value in if !custom { reference = value } }
    }
    private func apply() {
        do { try MacFXApplication.shared.setReferenceCurrency(reference); reference = service.configuration.referenceCurrency; custom = false; error = nil }
        catch { self.error = "请输入三位英文字母货币代码" }
    }
}

struct MacFXPreferencesView: View {
    enum Section { case all, display, source }
    var section: Section = .all
    var includeDirectoryAndSources = true
    var includeDisplayLists = true
    @ObservedObject private var service = MacFXApplication.shared.monitor
    @State private var interval = "30"
    @State private var openAge = "10"
    @State private var message: String?
    @State private var newCode = ""
    @State private var availableWidth: CGFloat = 0
    private var app: MacFXApplication { .shared }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            if section != .source {
                let layout = availableWidth >= 900 ? AnyLayout(HStackLayout(alignment:.top,spacing:16)) : AnyLayout(VStackLayout(spacing:16))
                VStack(spacing:0) { layout { displayCard; refreshCard } }.frame(maxWidth:.infinity)
                    .onGeometryChange(for:CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
            }
            if section != .display {
                MacSettingsCard(title:"报价来源",icon:"network",subtitle:"用于查询与换算；记账仍使用交易日参考报价。") {
                    MacSettingsRow(label:"优先来源") { MacSettingsMenu(selection:binding(\.sourcePolicy),options:sourceOptions).frame(maxWidth:320).accessibilityIdentifier("fxMonitorSource") }
                }.accessibilityElement(children:.contain).accessibilityIdentifier("fxSourcePolicyCard")
            }
            if section == .all {
                if includeDisplayLists { MacFXDisplaySettings() }
                if includeDirectoryAndSources {
                    MacSettingsCard(title:"货币目录",icon:"banknote") {
                        Text(MacFXCatalog.codes.joined(separator:"  ·  ")).appFont(.body)
                        HStack {
                            TextField("三位货币代码",text:$newCode).accessibilityIdentifier("fxDirectoryCode")
                            Button("添加") {
                                do { let code = try MacFXPair(base:newCode,quote:newCode).base; try MacSettingsStore.save(MacFXCatalog.codes.contains(code) ? MacFXCatalog.codes : MacFXCatalog.codes + [code],key:"v2_currencies"); app.reload(); newCode = "" }
                                catch { message = "请输入三位货币代码" }
                            }
                        }
                    }
                    MacFXSourceManagementCard()
                }
            }
            if let message { Text(message).appFont(.caption).foregroundStyle(.orange) }
            if let error = app.settingsError { Text(error).appFont(.caption).foregroundStyle(.red) }
        }.onAppear { interval = String(service.configuration.intervalMinutes); openAge = String(service.configuration.openMaxAgeMinutes) }
            .onChange(of:service.configuration.intervalMinutes) { _,value in interval = String(value) }
            .onChange(of:service.configuration.openMaxAgeMinutes) { _,value in openAge = String(value) }
    }
    private var displayCard: some View {
        MacSettingsCard(title:"显示偏好",icon:"number",subtitle:"仅影响菜单栏汇率列表与换算。") {
                    MacFXReferenceField()
                    Divider().padding(.vertical,3)
                    MacSettingsRow(label:"报价单位") { MacSettingsMenu(selection:binding(\.displayUnits),options:[("1单位",1),("100单位",100)]).frame(width:220).accessibilityIdentifier("fxSettingsUnits") }
                    MacSettingsRow(label:"汇率精度") { MacSettingsMenu(selection:binding(\.rateDigits),options:[2,4,6].map { ("\($0)位小数",$0) }).frame(width:220).accessibilityIdentifier("fxRateDigits") }
                    Text("默认币种用于新会话；不改当前输入或已保存金额。").appFont(.caption).foregroundStyle(.secondary)
                }.accessibilityElement(children:.contain).accessibilityIdentifier("fxDisplayPreferencesCard")
    }
    private var refreshCard: some View {
        MacSettingsCard(title:"更新方式",icon:"arrow.clockwise",subtitle:"自动刷新和打开页面时更新可以分别设置。") {
                    MacSettingsToggleRow(title:"自动刷新",value:binding(\.automatic)).accessibilityIdentifier("fxAutomatic")
                    if service.configuration.automatic {
                        minutesRow("每隔",text:$interval,suffix:"分钟刷新",identifier:"fxIntervalMinutes",button:"fxApplyInterval",apply:{ applyMinutes(interval,key:\.intervalMinutes) })
                        Text("可设置1–1440分钟；实际报价频率和额度以服务商为准。").appFont(.caption).foregroundStyle(.secondary)
                    }
                    Divider().padding(.vertical,5)
                    MacSettingsToggleRow(title:"打开查询页时更新",subtitle:"先显示缓存，超过设定时间再更新。",value:binding(\.refreshOnOpen)).accessibilityIdentifier("fxRefreshOnOpen")
                    if service.configuration.refreshOnOpen {
                        minutesRow("缓存超过",text:$openAge,suffix:"分钟再更新",identifier:"fxOpenAgeMinutes",button:"fxApplyOpenAge",apply:{ applyMinutes(openAge,key:\.openMaxAgeMinutes) })
                    }
                    Text(service.configuration.automatic ? "涨跌比较：较前次有效报价" : "涨跌比较：较前一自然日（系统时区）").appFont(.caption).foregroundStyle(.secondary)
                }.accessibilityElement(children:.contain).accessibilityIdentifier("fxRefreshPreferencesCard")
    }
    private func minutesRow(_ label:String,text:Binding<String>,suffix:String,identifier:String,button:String,apply:@escaping ()->Void) -> some View {
        HStack(spacing:10) {
            Text(label)
            TextField("分钟",text:text).frame(width:76).accessibilityIdentifier(identifier)
            Text(suffix)
            Spacer(minLength:8)
            Button("应用",action:apply).buttonStyle(MacSettingsButtonStyle(height:40)).accessibilityIdentifier(button)
        }.appFont(.body)
    }
    private var sourceOptions: [(String,String)] {
        MacFXSourceSelection.options(current:service.configuration.sourcePolicy)
    }
    private func binding<T>(_ key:WritableKeyPath<MacFXConfiguration,T>) -> Binding<T> {
        Binding(get:{service.configuration[keyPath:key]},set:{ value in DispatchQueue.main.async { app.update { $0[keyPath:key] = value } } })
    }
    private func applyMinutes(_ text:String,key:WritableKeyPath<MacFXConfiguration,Int>) {
        guard let number = Int(text), (1...1440).contains(number) else { message = "请输入1–1440分钟"; return }
        app.update { $0[keyPath:key] = number }; message = nil
    }
}

struct MacFXSourceManagementCard: View {
    @AppStorage("v2_fx_sources", store: MacPreferences.defaults) private var bytes = Data()
    @State private var editing: MacFXSource?
    @State private var removing: MacFXSource?
    @State private var error: String?
    private var sources: [MacFXSource] { (try? JSONDecoder().decode([MacFXSource].self, from: bytes)) ?? [] }
    var body: some View {
        MacSettingsCard(title: "汇率数据源", icon: "network", action: AnyView(Button("添加自定义 API", systemImage: "plus") { editing = MacFXTemplate.twelveData.source() }.accessibilityIdentifier("settingsFXAdd"))) {
            Label("系统数据源 · 内置免费", systemImage: "globe").appFont(.body, weight: .medium)
            ForEach(sources) { source in
                HStack {
                    MacFXSourceImage(source: source, size: 30)
                    Button(source.name) { editing = source }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("settingsFXSource-" + source.name)
                    Spacer()
                    Toggle("启用" + source.name, isOn: Binding(get: { source.enabled }, set: { enabled in
                        var values = sources; if let index = values.firstIndex(where: { $0.id == source.id }) { values[index].enabled = enabled }
                        do { try MacSettingsStore.save(values, key: "v2_fx_sources"); MacFXApplication.shared.reload() } catch { self.error = error.localizedDescription }
                    })).labelsHidden().toggleStyle(.switch).accessibilityIdentifier("fxEnable-" + source.name)
                    Button("删除", role: .destructive) { removing = source }
                }.frame(minHeight: 40)
            }
            if let error { Text(error).appFont(.caption, weight: .regular).foregroundStyle(.red) }
        }
        .sheet(item: $editing) { MacFXSourceEditor(source: $0, from: "USD", to: "CNY") }
        .alert("删除自定义数据源？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("取消", role: .cancel) { removing = nil }
            Button("删除", role: .destructive) { if let source = removing { do { try MacFXService.remove(source); MacFXApplication.shared.reload(); removing = nil } catch { self.error = error.localizedDescription } } }
        } message: { Text("同时移除对应 API Key，历史账目保持不变。") }
    }
}
