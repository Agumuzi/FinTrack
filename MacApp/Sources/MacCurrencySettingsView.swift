import SwiftUI
import AppKit
import SwiftData
import Charts

struct MacCurrencySettingsView: View {
    var wide: Bool
    @ObservedObject private var monitor = MacFXApplication.shared.monitor
    @ObservedObject private var query = MacFXApplication.shared.query
    @Environment(\.modelContext) private var context
    @AppStorage("base_currency") private var baseCurrency = "USD"
    @AppStorage("v2_currencies") private var currencyBytes = Data()
    @AppStorage("v2_disabled_currencies") private var disabledBytes = Data()
    @AppStorage("v2_fx_sources") private var sourceBytes = Data()
    @AppStorage("v2_fx_quotes") private var quoteBytes = Data()
    @State private var quoteBase = "USD"
    @State private var selected = "RUB"
    @State private var historyRange = "3个月"
    @State private var section = "通用"
    @State private var newCurrency = ""
    @State private var addingCurrency = false
    @State private var currencyAddError: String?
    @State private var editingSource: MacFXSource?
    @State private var removingSource: MacFXSource?
    @State private var showRebase = false
    @State private var menuOptionsExpanded = false
    @State private var busy = false
    @State private var error: String?
    @State private var message: String?
    private var codes: [String] { (try? JSONDecoder().decode([String].self, from: currencyBytes)) ?? ["USD", "RUB", "CNY", "EUR", "GBP", "JPY", "CHF", "HKD"] }
    private var disabled: [String] { (try? JSONDecoder().decode([String].self, from: disabledBytes)) ?? [] }
    private var sources: [MacFXSource] { (try? JSONDecoder().decode([MacFXSource].self, from: sourceBytes)) ?? [] }
    private var quotes: [MacFXQuote] { (try? JSONDecoder().decode([MacFXQuote].self, from: quoteBytes)) ?? [] }
    private var history: [MacFXQuote] {
        let days = ["1个月":30.0, "3个月":90, "6个月":180, "1年":365][historyRange]
        return quotes.filter { $0.from == quoteBase && $0.to == selected && (days == nil || $0.retrievedAt >= Date().addingTimeInterval(-days! * 86400)) }.sorted { $0.retrievedAt < $1.retrievedAt }
    }
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment:.leading,spacing:0) {
                HStack(spacing:8) {
                    ForEach(["通用","记账","菜单栏","数据源","历史记录"],id:\.self) { name in
                        Button { section = name } label: {
                            HStack(spacing:8) {
                                Image(systemName:sectionIcon(name)).appIconFont(19).accessibilityHidden(true)
                                Text(name).appFont(.body,weight:.semibold).lineLimit(1)
                            }.padding(.horizontal,8).frame(maxWidth:.infinity,minHeight:58)
                                .foregroundStyle(section == name ? MacUI.accent : .primary)
                                .background(section == name ? MacUI.accent.opacity(0.1) : MacOverviewStyle.card,in:RoundedRectangle(cornerRadius:10))
                                .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(section == name ? MacUI.accent.opacity(0.35) : .gray.opacity(0.14)))
                        }.buttonStyle(.plain).accessibilityLabel(name).accessibilityIdentifier("settingsSegment-" + name).accessibilityValue(section == name ? "已选中" : "未选中")
                    }
                }.accessibilityElement(children:.contain).accessibilityIdentifier("fxSettingsSections")
                    .appPadding(.horizontal,22).appPadding(.bottom,14)
                    .frame(maxWidth:MacUI.space(1320),alignment:.leading).frame(maxWidth:.infinity,alignment:.leading)
                Divider()
                ScrollView {
                    VStack(alignment:.leading,spacing:16) {
                        if let message { Text(message).appFont(.caption).foregroundStyle(.secondary).accessibilityIdentifier("fxRefreshMessage") }
                        if let error { Text(error).appFont(.caption).foregroundStyle(.red).accessibilityIdentifier("settingsFXError") }
                        switch section {
                        case "记账": accountingCard; bookCurrencyCard
                        case "菜单栏": menuSettings(height:geometry.size.height)
                        case "数据源": MacFXSystemSourceCard(); sourcesCard
                        case "历史记录": historyCard
                        default: currencyCard
                        }
                    }.appPadding(22).frame(maxWidth:MacUI.space(1320),alignment:.topLeading).frame(maxWidth:.infinity,alignment:.topLeading)
                }.accessibilityIdentifier("settingsScroll").id(section)
            }
        }
        .onAppear {
            consumeSectionRequest()
            quoteBase = baseCurrency
        }
        .onChange(of:query.settingsSectionRequest) { _,_ in consumeSectionRequest() }
        .onChange(of:section) { _,name in
            message = nil; error = nil
            if name == "菜单栏" { Task { await monitor.pageOpened() } }
        }
        .sheet(item: $editingSource) { MacFXSourceEditor(source: $0, from: quoteBase, to: selected == quoteBase ? "CNY" : selected) }
        .sheet(isPresented: $showRebase) { MacCurrencyRebaseView() }
        .alert("删除自定义数据源？", isPresented: Binding(get: { removingSource != nil }, set: { if !$0 { removingSource = nil } })) {
            Button("取消", role: .cancel) { removingSource = nil }
            Button("删除", role: .destructive) { if let removingSource { do { try MacFXService.remove(removingSource); self.removingSource = nil } catch { self.error = error.localizedDescription } } }
        } message: { Text("同时移除对应 API Key，历史交易与报价保持不变。") }
    }
    private func consumeSectionRequest() {
        guard let requested = query.settingsSectionRequest else { return }
        if ["通用","记账","菜单栏","数据源","历史记录"].contains(requested) { section = requested }
        query.settingsSectionRequest = nil
    }
    private func sectionIcon(_ name:String) -> String {
        switch name { case "通用":"globe"; case "记账":"book.closed"; case "菜单栏":"menubar.rectangle"; case "数据源":"network"; default:"clock.arrow.circlepath" }
    }
    private var accountingCard: some View {
        MacSettingsCard(title:"记账汇率",icon:"book.closed",subtitle:"主窗口、快速记账及其他记账场景使用，不影响菜单栏换算。") {
            MacFXScenarioSourcePicker(scenario:.accounting)
            HStack {
                Text("获取时核验交易日期，保存前仍可手动调整金额与汇率。").appFont(.caption).foregroundStyle(.secondary)
                Spacer(minLength:12)
                Button("管理数据源") { section = "数据源" }.accessibilityIdentifier("fxAccountingManageSources")
            }
        }.accessibilityElement(children:.contain).accessibilityIdentifier("fxAccountingSettingsCard")
    }
    private func menuSettings(height:CGFloat) -> some View {
        VStack(alignment:.leading,spacing:16) {
            MacSettingsCard(title:"菜单栏汇率",icon:"menubar.rectangle",subtitle:"用于汇率列表和换算；快速记账仍使用记账设置。") {
                MacFXScenarioSourcePicker(scenario:.menuBar)
                HStack {
                    MacFXLastUpdatedView(service:monitor)
                    Button("更新菜单栏汇率",systemImage:"arrow.clockwise") { Task { await refresh() } }.disabled(busy).accessibilityIdentifier("settingsRefreshRates")
                }
            }.accessibilityElement(children:.contain).accessibilityIdentifier("fxMenuSettingsCard")
            VStack(alignment:.leading,spacing:0) {
                Button { menuOptionsExpanded.toggle() } label: {
                    HStack {
                        Label("显示与更新",systemImage:"slider.horizontal.3").appFont(.body,weight:.semibold)
                        Spacer(); Image(systemName:menuOptionsExpanded ? "chevron.up" : "chevron.down").appIconFont(13)
                    }.frame(minHeight:30).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("fxMenuPreferencesToggle").accessibilityValue(menuOptionsExpanded ? "已展开" : "已收起")
                if menuOptionsExpanded { MacFXPreferencesView(section:.display,includeDirectoryAndSources:false,includeDisplayLists:false).padding(.top,12) }
            }.padding(16).background(MacOverviewStyle.card,in:RoundedRectangle(cornerRadius:13)).accessibilityElement(children:.contain).accessibilityIdentifier("fxMenuPreferencesGroup")
            MacFXDisplaySettings(availableHeight:min(height,470))
        }
    }
    private var directoryAddForm: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("添加货币").appFont(.section,weight:.semibold)
            Text("输入三位英文字母代码，添加到统一货币目录。").appFont(.caption).foregroundStyle(.secondary)
            HStack(spacing:10) {
                MacCurrencyFlag(code:newCurrency.uppercased(),width:24).fixedSize()
                TextField("货币代码，如 CAD",text:$newCurrency).textFieldStyle(MacSettingsFieldStyle()).accessibilityIdentifier("fxDirectoryCustomCode")
            }
            if let currencyAddError { Text(currencyAddError).appFont(.caption).foregroundStyle(.red) }
            HStack {
                Button("取消") { addingCurrency = false; newCurrency = ""; currencyAddError = nil }.accessibilityIdentifier("fxDirectoryCancel")
                Spacer()
                Button("添加") {
                    do {
                        let code = try MacCurrency.code(newCurrency)
                        try MacSettingsStore.save(Array(Set(codes + [code])).sorted(),key:"v2_currencies")
                        selected = code; newCurrency = ""; currencyAddError = nil; addingCurrency = false
                    } catch { currencyAddError = MacLocalization.error(error) }
                }.buttonStyle(MacSettingsButtonStyle(primary:true,height:40)).disabled((try? MacCurrency.code(newCurrency)) == nil).accessibilityIdentifier("fxDirectoryConfirm")
            }
        }.appFont(.body).padding(18).frame(width:340)
    }
    private var currencyCard: some View {
        MacSettingsCard(title:"货币目录",icon:"banknote",subtitle:"记账和查询使用的统一货币目录。",action:AnyView(Button("添加货币",systemImage:"plus") { addingCurrency = true }.accessibilityIdentifier("settingsCurrencyAdd").popover(isPresented:$addingCurrency) { directoryAddForm })) {
            HStack {
                Text("用于软件各处的货币选择，菜单栏列表在“菜单栏”中单独管理。").appFont(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(codes.count) 个币种").appFont(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("货币"); Spacer()
                Text("状态").frame(width:80); Color.clear.frame(width:28,height:1)
            }.appFont(.caption).foregroundStyle(.secondary).padding(.horizontal,10).frame(minHeight:32)
            VStack(spacing:0) {
                ForEach(codes,id:\.self) { code in currencyRow(code); if code != codes.last { Divider() } }
            }
        }.accessibilityElement(children:.contain).accessibilityIdentifier("fxCurrencyDirectoryCard")
    }
    private var bookCurrencyCard: some View {
        MacSettingsCard(title:"账本本位币",icon:"books.vertical",subtitle:"与查询参考币种分别管理。") {
            HStack {
                MacCurrencyFlag(code:baseCurrency,width:24)
                Text(baseCurrency).appFont(.body,weight:.semibold)
                Spacer()
                Button("更改账本币种…") { showRebase = true }.accessibilityIdentifier("fxChangeBookCurrency")
            }
        }.accessibilityElement(children:.contain).accessibilityIdentifier("fxBookCurrencyCard")
    }
    private func currencyRow(_ code: String) -> some View {
        HStack(spacing:10) {
            currencyChoice(code).frame(maxWidth:.infinity,alignment:.leading)
            currencyStatus(code).frame(width:80)
            currencyActions(code).frame(width:28)
        }.padding(.horizontal,10).padding(.vertical,8).frame(minHeight:56)
            .background(selected == code ? MacSettingsVisual.accent.opacity(0.045) : .clear)
    }
    private func currencyChoice(_ code: String) -> some View {
        Button { selected = code; section = "历史记录" } label: {
            HStack(spacing:10) {
                MacCurrencyFlag(code:code,width:26).fixedSize()
                VStack(alignment:.leading,spacing:3) {
                    Text(code).appFont(.body,weight:.semibold)
                    Text(MacSettingsVisual.currencyName(code)).appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength:0)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("settingsCurrency-" + code)
    }
    private func currencyStatus(_ code: String) -> some View {
        Text(code == baseCurrency ? "账本币种" : disabled.contains(code) ? "未启用" : "使用中")
            .appFont(.caption, weight: .medium, design: .default).foregroundStyle(disabled.contains(code) ? Color.secondary : Color.green)
            .appPadding(.horizontal, 8).appPadding(.vertical, 4)
            .background(disabled.contains(code) ? Color.gray.opacity(0.08) : Color.green.opacity(0.1), in: Capsule())
    }
    private func currencyActions(_ code: String) -> some View {
        Menu {
            Button(disabled.contains(code) ? "启用货币" : "停用货币") { toggleCurrency(code) }.disabled(code == baseCurrency)
            Button("从列表移除", role: .destructive) { removeCurrency(code) }.disabled(code == baseCurrency)
        } label: { Image(systemName: "ellipsis").appIconFont(16).frame(width: MacUI.space(28), height: MacUI.space(28)) }
            .menuStyle(.borderlessButton).fixedSize()
    }
    private var sourcesCard: some View {
        MacSettingsCard(title: "自定义数据源", icon: "network", action: AnyView(Button("添加自定义 API", systemImage: "plus") { editingSource = MacFXTemplate.twelveData.source() }.accessibilityIdentifier("settingsFXAdd")), compactHeader: true) {
            VStack(spacing: MacUI.space(0)) {
                if sources.isEmpty { Text("可选扩展。无需添加自定义API，系统数据源也能提供汇率。").appFont(.caption).foregroundStyle(.secondary).padding(.vertical,12) }
                ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                    sourceRow(source, index: index)
                    Divider()
                }
            }
        }.accessibilityElement(children:.contain).accessibilityIdentifier("fxSourcesManagementCard")
    }
    private func sourceRow(_ source: MacFXSource, index: Int) -> some View {
HStack(spacing: MacUI.space(8)) {
                        MacFXSourceImage(source: source, size: 29)
                        Button { editingSource = source } label: { VStack(alignment: .leading, spacing: MacUI.space(4)) { Text(source.name).appFont(.body, weight: .semibold, design: .default).lineLimit(1); Text(index < 2 && MacSettingsVisual.preview ? "官方汇率数据 · 演示" : "自定义 API").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityIdentifier("settingsFXSource-" + source.name)
                        Text(monitor.quotes.filter { $0.identity.sourceID == source.id.uuidString }.max { $0.retrievedAt < $1.retrievedAt }.map { MacDateDisplay.string($0.retrievedAt) + "\n" + MacDisplayPreferences.time($0.retrievedAt) } ?? "尚未更新").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).frame(width: MacUI.space(70))
                        Text(source.enabled ? "启用" : "停用").appFont(.caption, weight: .medium, design: .default).foregroundStyle(source.enabled ? Color.green : Color.secondary).appPadding(5).background(source.enabled ? Color.green.opacity(0.09) : .gray.opacity(0.05), in: Capsule())
                        Toggle("启用" + source.name, isOn: Binding(get: { source.enabled }, set: { toggle(source, enabled: $0) })).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(.blue).accessibilityIdentifier("fxEnable-" + source.name)
                        Menu { Button("编辑") { editingSource = source }; Button("删除", role: .destructive) { removingSource = source } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                    }.frame(minHeight: MacUI.space(49))
    }
    private var historyCard: some View {
        MacSettingsCard(title:"已保存的报价",icon:"chart.xyaxis.line",subtitle:"查看已保存报价。已保存账目继续使用各自的金额快照。") {
            VStack(alignment:.leading,spacing:12) {
                HStack {
                    Text("参考币种").appFont(.caption).foregroundStyle(.secondary)
                    MacCurrencyMenu(selection:$quoteBase,codes:codes,identifier:"currencyHistoryBaseMenu")
                    Spacer()
                }
                if wide {
                    HStack {
                        MacCurrencyMenu(selection:$selected,codes:codes.filter { $0 != quoteBase },identifier:"currencyHistoryCodeMenu")
                        Spacer(minLength:16)
                        MacSettingsSegments(selection:$historyRange,options:["1个月","3个月","6个月","1年","全部"],minimumOptionWidth:46).frame(maxWidth:420)
                    }
                } else {
                    MacCurrencyMenu(selection:$selected,codes:codes.filter { $0 != quoteBase },identifier:"currencyHistoryCodeMenu")
                    MacSettingsSegments(selection:$historyRange,options:["1个月","3个月","6个月","1年","全部"],minimumOptionWidth:46)
                }
            }
            if history.isEmpty {
                VStack(spacing:10) {
                    Image(systemName:"chart.xyaxis.line").appIconFont(32).foregroundStyle(.secondary).accessibilityHidden(true)
                    Text("暂无已保存报价").appFont(.body,weight:.semibold)
                    Text("新的历史走势可在汇率列表卡片中展开查看。").appFont(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,minHeight:220).accessibilityElement(children:.contain).accessibilityIdentifier("fxHistoryEmpty")
            } else {
                Chart(history) { point in
                    AreaMark(x:.value("日期",point.retrievedAt),yStart:.value("基线",minimum * Double(monitor.configuration.displayUnits) * 0.97),yEnd:.value("汇率",point.rate * Double(monitor.configuration.displayUnits))).foregroundStyle(LinearGradient(colors:[.red.opacity(0.2),.red.opacity(0.01)],startPoint:.top,endPoint:.bottom))
                    LineMark(x:.value("日期",point.retrievedAt),y:.value("汇率",point.rate * Double(monitor.configuration.displayUnits))).foregroundStyle(.red).lineStyle(StrokeStyle(lineWidth:1.6))
                }.chartYScale(domain:minimum * Double(monitor.configuration.displayUnits) * 0.97...maximum * Double(monitor.configuration.displayUnits) * 1.03).chartXAxis { AxisMarks(values:.stride(by:.month)) { _ in AxisValueLabel(format:.dateTime.month(.twoDigits).day()) } }.frame(minHeight:220)
                HStack(spacing:0) {
                    historyMetric(MacFXMath.formatted(minimum * Double(monitor.configuration.displayUnits),digits:monitor.configuration.rateDigits),"区间最低")
                    Divider()
                    historyMetric(MacFXMath.formatted(maximum * Double(monitor.configuration.displayUnits),digits:monitor.configuration.rateDigits),"区间最高")
                    Divider(); historyMetric(change,"区间变化")
                }.frame(height:64).padding(8).background(.gray.opacity(0.04),in:RoundedRectangle(cornerRadius:8))
            }
        }.accessibilityElement(children:.contain).accessibilityIdentifier("fxHistoryRecordsCard")
    }
    private var minimum: Double { history.map(\.rate).min() ?? 0 }
    private var maximum: Double { history.map(\.rate).max() ?? 1 }
    private var change: String { guard let first = history.first, let last = history.last else { return "—" }; return String(format: "%+.1f%%", (last.rate / first.rate - 1) * 100) }
    private func historyMetric(_ value: String, _ title: String) -> some View { VStack(spacing: MacUI.space(6)) { Text(value).appFont(.body, weight: .bold, design: .default).monospacedDigit(); Text(title).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }.frame(maxWidth: .infinity) }
    private func toggleCurrency(_ code: String) { var all = disabled; if all.contains(code) { all.removeAll { $0 == code } } else { all.append(code) }; do { try MacSettingsStore.save(all, key: "v2_disabled_currencies") } catch { self.error = error.localizedDescription } }
    private func removeCurrency(_ code: String) { do { try MacSettingsStore.save(codes.filter { $0 != code }, key: "v2_currencies") } catch { self.error = error.localizedDescription } }
    private func toggle(_ source: MacFXSource, enabled: Bool) { var s = source; s.enabled = enabled; do { try MacSettingsStore.save(sources.map { $0.id == s.id ? s : $0 }, key: "v2_fx_sources") } catch { self.error = error.localizedDescription } }
    private func refresh() async {
        busy = true; defer { busy = false }; error = nil; message = nil
        await monitor.refresh(reason:.manual)
        message = monitor.status; error = monitor.errors.values.sorted().first
    }
}

struct MacFXSourceEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var source: MacFXSource
    var from: String
    var to: String
    @State private var template = MacFXTemplate.custom
    @State private var key = ""
    @State private var result: String?
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(15)) {
            Text("自定义汇率 API").appFont(.dialogTitle, weight: .semibold)
            HStack(spacing: MacUI.space(14)) {
                MacFXSourceImage(source: source, size: 48)
                MacImageImportControl(data: Binding(get: { source.imageData ?? Data() }, set: { source.imageData = $0.isEmpty ? nil : $0 }), cropTitle: "裁切数据源图片", label: source.name, identifier: "fxSourceImage")
                Spacer()
            }
            MacSettingsRow(label: "数据源模板", labelWidth: 100) {
                MacSettingsMenu(selection: $template, options: MacFXTemplate.allCases.map { ($0.title, $0) }).accessibilityIdentifier("fxTemplateMenu")
            }
            if template == .custom {
                TextField("名称", text: $source.name).accessibilityIdentifier("fxSourceName")
                TextField("HTTPS URL 模板", text: $source.urlTemplate).accessibilityIdentifier("fxSourceURL")
                TextField("汇率 JSON 路径，如 rates.{quote}", text: $source.ratePath).accessibilityIdentifier("fxSourcePath")
                TextField("报价日期 JSON 路径（历史汇率必填）", text: $source.datePath).accessibilityIdentifier("fxSourceDatePath")
                TextField("日级报价时区，如 UTC；未知可留空", text: Binding(get: { source.dateTimeZoneID ?? "" }, set: { source.dateTimeZoneID = $0.isEmpty ? nil : $0 })).accessibilityIdentifier("fxSourceTimeZone")
                Text("占位符：{base}、{quote}、{baseLower}、{quoteLower}、{date}、{key}。汇率方向：1 base = rate quote。").appFont(.caption).foregroundStyle(.secondary)
            } else {
                Text(template == .twelveData ? "填写 Twelve Data 的 API Key 即可使用。" : "填写 Open Exchange Rates 的 App ID 即可使用，支持任意基准币种。")
                    .appFont(.caption).foregroundStyle(.secondary)
            }
            SecureField(template == .openExchangeRates ? "App ID（保存到钥匙串）" : "API Key（保存到钥匙串）", text: $key).accessibilityIdentifier("fxSourceKey")
            Toggle("启用此数据源", isOn: $source.enabled)
            if let result { Text(result).foregroundStyle(.green).accessibilityIdentifier("fxConnectionResult") }
            if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("fxSourceError") }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(busy ? "测试中…" : "连接测试") { Task { await test() } }.disabled(busy).accessibilityIdentifier("fxConnectionTest")
                Spacer()
                Button("保存") { do { if template != .custom && key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw MacSettingsFailure.invalid("请填写 API Key / App ID") }; try MacFXService.save(source, key: key); dismiss() } catch { self.error = MacLocalization.error(error) } }.disabled(busy).accessibilityIdentifier("fxSourceSave")
            }
        }.appPadding(26).appDialog(width: 570)
        .onAppear { template = source.provider.flatMap(MacFXTemplate.init(rawValue:)) ?? .custom; do { key = try MacFXSecrets.read(source.id) } catch { self.error = error.localizedDescription } }
        .onChange(of: template) { _, value in
            guard source.provider != (value == .custom ? nil : value.rawValue) else { return }
            let old = source
            source = value.source(id: old.id); source.enabled = old.enabled; source.imageData = old.imageData
            result = nil; error = nil
        }
    }
    private func test() async {
        busy = true; defer { busy = false }; error = nil; result = nil
        do {
            try source.validate()
            let data = try await MacFXService.requestData(source, from: from, to: to, date: Date(), keyOverride: key)
            let (rate, _) = try MacFXService.decode(data, source: source, from: from, to: to, date: nil, preserveRawRate: true)
            result = "连接成功：1 \(from) = \(rate) \(to)"
        }
        catch { self.error = MacLocalization.error(error) }
    }
}

struct MacFXSourceImage: View {
    var source: MacFXSource
    var size: CGFloat = 30
    var body: some View {
        Group {
            if let bytes = source.imageData, let image = NSImage(data: bytes) {
                Image(nsImage: image).resizable().scaledToFit()
            } else if MacSettingsVisual.preview && source.name == "ECB（欧洲央行）" { MacCurrencyFlag(code: "EUR", width: size) }
            else if MacSettingsVisual.preview && source.name == "俄罗斯央行（CBR）" { MacCurrencyFlag(code: "RUB", width: size) }
            else { Image(systemName: "globe").resizable().scaledToFit().foregroundStyle(.secondary).appPadding(2) }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityHidden(true)
    }
}
