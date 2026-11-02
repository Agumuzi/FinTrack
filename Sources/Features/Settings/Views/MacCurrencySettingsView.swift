import SwiftUI
import AppKit
import SwiftData
import Charts
import UniformTypeIdentifiers

struct MacCurrencySettingsView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
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
    @State private var draggedCurrency: String?
    @State private var directoryDraft: [String] = []
    private var directoryCodes: [String] { directoryDraft.isEmpty ? MacCurrencyDirectory.ordered(codes, base: baseCurrency) : MacCurrencyDirectory.ordered(directoryDraft, base: baseCurrency) }
    @State private var busy = false
    @State private var error: String?
    @State private var message: String?
    private var codes: [String] { (try? JSONDecoder().decode([String].self, from: currencyBytes)) ?? [] }
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
                                Text(L10n.builtIn(name)).appFont(.body,weight:.semibold).lineLimit(1)
                            }.padding(.horizontal,8).frame(maxWidth:.infinity,minHeight:58)
                                .foregroundStyle(section == name ? MacUI.accent : .primary)
                                .background(section == name ? MacUI.accent.opacity(0.1) : MacOverviewStyle.card,in:RoundedRectangle(cornerRadius:10))
                                .overlay(RoundedRectangle(cornerRadius:10).strokeBorder(section == name ? MacUI.accent.opacity(0.35) : .gray.opacity(0.14)))
                        }.buttonStyle(MacInteractiveButtonStyle()).accessibilityLabel(L10n.builtIn(name)).accessibilityIdentifier("settingsSegment-" + name).accessibilityValue(section == name ? L10n.text("mac.currencySettingsView.ForEach.a737fd72b0") : L10n.text("mac.currencySettingsView.ForEach.0e0c21de69"))
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
        .onChange(of: baseCurrency) { directoryDraft = []; draggedCurrency = nil }
        .onDisappear { directoryDraft = []; draggedCurrency = nil }
        .onChange(of:section) { _,name in
            message = nil; error = nil
            if name == "菜单栏" { Task { await monitor.pageOpened() } }
        }
        .sheet(item: $editingSource) { MacFXSourceEditor(source: $0, from: quoteBase, to: selected == quoteBase ? "CNY" : selected) }
        .sheet(isPresented: $showRebase) { MacCurrencyRebaseView() }
        .alert(L10n.text("mac.currencySettingsView.body.ce6d2a9642"), isPresented: Binding(get: { removingSource != nil }, set: { if !$0 { removingSource = nil } })) {
            Button(L10n.text("mac.currencySettingsView.body.2cd0f3be87"), role: .cancel) { removingSource = nil }
            Button(L10n.text("mac.currencySettingsView.body.2f9daa8289"), role: .destructive) { if let removingSource { Task {do {try await MacFXService.removeAsync(removingSource);self.removingSource=nil}catch{self.error=error.localizedDescription}} } }
        } message: { Text(L10n.text("mac.currencySettingsView.body.51c5b22f4f")) }
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
        MacSettingsCard(title:L10n.text("mac.currencySettingsView.accountingCard.77084c2fe4"),icon:"book.closed",subtitle:L10n.text("mac.currencySettingsView.accountingCard.b8f9861d55")) {
            MacFXScenarioSourcePicker(scenario:.accounting)
            HStack {
                Text(L10n.text("mac.currencySettingsView.accountingCard.96604e0c09")).appFont(.caption).foregroundStyle(.secondary)
                Spacer(minLength:12)
                Button(L10n.text("mac.currencySettingsView.accountingCard.715ced418f")) { section = L10n.text("mac.currencySettingsView.accountingCard.186be2232e") }.accessibilityIdentifier("fxAccountingManageSources")
            }
        }.accessibilityElement(children:.contain).accessibilityIdentifier("fxAccountingSettingsCard")
    }
    private func menuSettings(height:CGFloat) -> some View {
        VStack(alignment:.leading,spacing:16) {
            MacSettingsCard(title:L10n.text("mac.currencySettingsView.menuSettings.16608b170f"),icon:"menubar.rectangle",subtitle:L10n.text("mac.currencySettingsView.menuSettings.4f2caa744f")) {
                MacFXScenarioSourcePicker(scenario:.menuBar)
                HStack {
                    MacFXLastUpdatedView(service:monitor)
                    Button(L10n.text("mac.currencySettingsView.menuSettings.e20e7c296d"),systemImage:"arrow.clockwise") { Task { await refresh() } }.disabled(busy).accessibilityIdentifier("settingsRefreshRates")
                }
            }.accessibilityElement(children:.contain).accessibilityIdentifier("fxMenuSettingsCard")
            VStack(alignment:.leading,spacing:0) {
                Button { menuOptionsExpanded.toggle() } label: {
                    HStack {
                        Label(L10n.text("mac.currencySettingsView.menuSettings.5977e70b01"),systemImage:"slider.horizontal.3").appFont(.body,weight:.semibold)
                        Spacer(); Image(systemName:menuOptionsExpanded ? "chevron.up" : "chevron.down").appIconFont(13)
                    }.frame(minHeight:30).contentShape(Rectangle())
                }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("fxMenuPreferencesToggle").accessibilityValue(menuOptionsExpanded ? L10n.text("mac.currencySettingsView.menuSettings.df647b73b9") : L10n.text("mac.currencySettingsView.menuSettings.e64447db76"))
                if menuOptionsExpanded { MacFXPreferencesView(section:.display,includeDirectoryAndSources:false,includeDisplayLists:false).padding(.top,12) }
            }.padding(16).background(MacOverviewStyle.card,in:RoundedRectangle(cornerRadius:13)).accessibilityElement(children:.contain).accessibilityIdentifier("fxMenuPreferencesGroup")
            MacFXDisplaySettings(availableHeight:min(height,470))
        }
    }
    private var directoryAddForm: some View {
        VStack(alignment:.leading,spacing:12) {
            Text(L10n.text("mac.currencySettingsView.directoryAddForm.e23aee63c4")).appFont(.section,weight:.semibold)
            Text(L10n.text("mac.currencySettingsView.directoryAddForm.540feb7595")).appFont(.caption).foregroundStyle(.secondary)
            HStack(spacing:10) {
                MacCurrencyFlag(code:newCurrency.uppercased(),width:24).fixedSize()
                TextField(L10n.text("mac.currencySettingsView.directoryAddForm.37c5e6b8cb"),text:$newCurrency).textFieldStyle(MacSettingsFieldStyle()).accessibilityIdentifier("fxDirectoryCustomCode")
            }
            if let currencyAddError { Text(currencyAddError).appFont(.caption).foregroundStyle(.red) }
            HStack {
                Button(L10n.text("mac.currencySettingsView.directoryAddForm.2cd0f3be87")) { addingCurrency = false; newCurrency = ""; currencyAddError = nil }.accessibilityIdentifier("fxDirectoryCancel")
                Spacer()
                Button(L10n.text("mac.currencySettingsView.directoryAddForm.7a8a11ead5")) {
                    do {
                        let code = try MacCurrency.code(newCurrency)
                        try MacSettingsStore.save(MacCurrencyDirectory.ordered(codes + [code], base: baseCurrency),key:"v2_currencies")
                        selected = code; newCurrency = ""; currencyAddError = nil; addingCurrency = false
                    } catch { currencyAddError = MacLocalization.error(error) }
                }.buttonStyle(MacSettingsButtonStyle(primary:true,height:40)).disabled((try? MacCurrency.code(newCurrency)) == nil).accessibilityIdentifier("fxDirectoryConfirm")
            }
        }.appFont(.body).padding(18).frame(width:340)
    }
    private var currencyCard: some View {
        MacSettingsCard(title:L10n.text("mac.currencySettingsView.currencyCard.441d6be316"),icon:"banknote",subtitle:L10n.text("mac.currencySettingsView.currencyCard.f5bf343017"),action:AnyView(Button(L10n.text("mac.currencySettingsView.AnyView.e23aee63c4"),systemImage:"plus") { addingCurrency = true }.accessibilityIdentifier("settingsCurrencyAdd").popover(isPresented:$addingCurrency) { directoryAddForm })) {
            HStack {
                Text(L10n.text("mac.currencySettingsView.currencyCard.d1f6c31961")).appFont(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(L10n.format("mac.currencySettingsView.currencyCard.1244ace08a", Int64(directoryCodes.count))).appFont(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(L10n.text("mac.currencySettingsView.currencyCard.04ee13cd1d")); Spacer()
                Text(L10n.text("mac.currencySettingsView.currencyCard.6320b4a872")).frame(width:max(80,MacUI.fontTier.bodySize * 4.5)); Color.clear.frame(width:28,height:1)
            }.appFont(.caption).foregroundStyle(.secondary).padding(.horizontal,10).frame(minHeight:32)
            VStack(spacing:0) {
                ForEach(directoryCodes,id:\.self) { code in
                    currencyRow(code)
                        .onDrop(of: [.text], delegate: MacDirectoryDrop(target: code, base: baseCurrency, dragged: $draggedCurrency, order: $directoryDraft, save: saveDirectory))
                    if code != directoryCodes.last { Divider() }
                }
                Color.clear.frame(height: 18).contentShape(Rectangle()).onDrop(of: [.text], delegate: MacDirectoryDrop(target: nil, base: baseCurrency, dragged: $draggedCurrency, order: $directoryDraft, save: saveDirectory))
            }
        }.accessibilityElement(children:.contain).accessibilityIdentifier("fxCurrencyDirectoryCard")
    }
    private func saveDirectory(_ order: [String]) { do { try MacSettingsStore.save(MacCurrencyDirectory.ordered(order, base: baseCurrency), key: "v2_currencies") } catch { self.error = MacLocalization.error(error) } }
    private var bookCurrencyCard: some View {
        MacSettingsCard(title:L10n.text("mac.currencySettingsView.bookCurrencyCard.abf35c9ecc"),icon:"books.vertical",subtitle:L10n.text("mac.currencySettingsView.bookCurrencyCard.6d1581d8e3")) {
            HStack {
                MacCurrencyFlag(code:baseCurrency,width:24)
                Text(baseCurrency).appFont(.body,weight:.semibold)
                Spacer()
                Button(L10n.text("mac.currencySettingsView.bookCurrencyCard.c029a1ca4f")) { showRebase = true }.accessibilityIdentifier("fxChangeBookCurrency")
            }
        }.accessibilityElement(children:.contain).accessibilityIdentifier("fxBookCurrencyCard")
    }
    private func currencyRow(_ code: String) -> some View {
        HStack(spacing:10) {
            if code == baseCurrency { Image(systemName: "pin.fill").foregroundStyle(.secondary).frame(width: 16) }
            else { Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).frame(width: 16, height: 32).contentShape(Rectangle()).onDrag { directoryDraft = MacCurrencyDirectory.ordered(codes, base: baseCurrency); draggedCurrency = code; return NSItemProvider(object: ("FinTrackCurrency:" + code) as NSString) } }
            currencyChoice(code).frame(maxWidth:.infinity,alignment:.leading)
            currencyStatus(code).frame(width:max(80,MacUI.fontTier.bodySize * 4.5))
            currencyActions(code).frame(width:28)
        }.padding(.horizontal,10).padding(.vertical,6).frame(minHeight:44)
            .background(selected == code ? MacSettingsVisual.accent.opacity(0.045) : .clear)
    }
    private func currencyChoice(_ code: String) -> some View {
        Button { selected = code; section = L10n.text("mac.currencySettingsView.currencyChoice.5467922dce") } label: {
            HStack(spacing:10) {
                MacCurrencyFlag(code:code,width:26).fixedSize()
                Text(code).appFont(.body,weight:.semibold).lineLimit(1).frame(width:max(48,MacUI.fontTier.bodySize * 3),alignment:.leading)
                Text(MacSettingsVisual.currencyName(code)).appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength:0)
            }.contentShape(Rectangle())
        }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("settingsCurrency-" + code)
    }
    private func currencyStatus(_ code: String) -> some View {
        Text(code == baseCurrency ? L10n.text("mac.currencySettingsView.currencyStatus.811a5f783e") : disabled.contains(code) ? L10n.text("mac.currencySettingsView.currencyStatus.f95ea7f4c0") : L10n.text("mac.currencySettingsView.currencyStatus.fa48e89389"))
            .appFont(.caption, weight: .medium, design: .default).foregroundStyle(disabled.contains(code) ? Color.secondary : Color.green)
            .appPadding(.horizontal, 8).appPadding(.vertical, 4)
            .background(disabled.contains(code) ? Color.gray.opacity(0.08) : Color.green.opacity(0.1), in: Capsule())
    }
    private func currencyActions(_ code: String) -> some View {
        Menu {
            Button(disabled.contains(code) ? L10n.text("mac.currencySettingsView.Menu.a574f875b0") : L10n.text("mac.currencySettingsView.Menu.b55dc6bab6")) { toggleCurrency(code) }.disabled(code == baseCurrency)
            Button(L10n.text("mac.currencySettingsView.Menu.e29e4fe7be"), role: .destructive) { removeCurrency(code) }.disabled(code == baseCurrency)
        } label: { Image(systemName: "ellipsis").appIconFont(16).frame(width: MacUI.space(28), height: MacUI.space(28)) }
            .menuStyle(.borderlessButton).fixedSize()
    }
    private var sourcesCard: some View {
        MacSettingsCard(title: L10n.text("mac.currencySettingsView.sourcesCard.c17f50d78f"), icon: "network", action: AnyView(Button(L10n.text("mac.currencySettingsView.AnyView.ae3676ce6b"), systemImage: "plus") { editingSource = MacFXTemplate.twelveData.source() }.accessibilityIdentifier("settingsFXAdd")), compactHeader: true) {
            VStack(spacing: MacUI.space(0)) {
                if sources.isEmpty { Text(L10n.text("mac.currencySettingsView.sourcesCard.203e0c4ddf")).appFont(.caption).foregroundStyle(.secondary).padding(.vertical,12) }
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
                        Button { editingSource = source } label: { VStack(alignment: .leading, spacing: MacUI.space(4)) { Text(source.name).appFont(.body, weight: .semibold, design: .default).lineLimit(1); Text(index < 2 && MacSettingsVisual.preview ? L10n.text("mac.currencySettingsView.sourceRow.57e316acb2") : L10n.text("mac.currencySettingsView.sourceRow.cadf64cf74")).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("settingsFXSource-" + source.name)
                        Text(monitor.quotes.filter { $0.identity.sourceID == source.id.uuidString }.max { $0.retrievedAt < $1.retrievedAt }.map { MacDateDisplay.string($0.retrievedAt) + "\n" + MacDisplayPreferences.time($0.retrievedAt) } ?? L10n.text("mac.currencySettingsView.sourceRow.bee4c96edd")).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).frame(width: MacUI.space(70))
                        Text(source.enabled ? L10n.text("mac.currencySettingsView.sourceRow.f4f0ead111") : L10n.text("mac.currencySettingsView.sourceRow.4e6fd0e28c")).appFont(.caption, weight: .medium, design: .default).foregroundStyle(source.enabled ? Color.green : Color.secondary).appPadding(5).background(source.enabled ? Color.green.opacity(0.09) : .gray.opacity(0.05), in: Capsule())
                        Toggle(L10n.text("mac.currencySettingsView.sourceRow.f4f0ead111") + source.name, isOn: Binding(get: { source.enabled }, set: { toggle(source, enabled: $0) })).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(.blue).accessibilityIdentifier("fxEnable-" + source.name)
                        Menu { Button(L10n.text("mac.currencySettingsView.Menu.0518365699")) { editingSource = source }; Button(L10n.text("mac.currencySettingsView.Menu.2f9daa8289"), role: .destructive) { removingSource = source } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                    }.frame(minHeight: MacUI.space(49))
    }
    private var historyCard: some View {
        MacSettingsCard(title:L10n.text("mac.currencySettingsView.historyCard.c6bbc7044e"),icon:"chart.xyaxis.line",subtitle:L10n.text("mac.currencySettingsView.historyCard.7f18453b63")) {
            VStack(alignment:.leading,spacing:12) {
                HStack {
                    Text(L10n.text("mac.currencySettingsView.historyCard.42c9eb8c53")).appFont(.caption).foregroundStyle(.secondary)
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
                    Text(L10n.text("mac.currencySettingsView.historyCard.7d033e7470")).appFont(.body,weight:.semibold)
                    Text(L10n.text("mac.currencySettingsView.historyCard.4d1cb3b6ea")).appFont(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,minHeight:220).accessibilityElement(children:.contain).accessibilityIdentifier("fxHistoryEmpty")
            } else {
                Chart(history) { point in
                    AreaMark(x:.value(L10n.text("mac.currencySettingsView.AreaMark.70d0c1b336"),point.retrievedAt),yStart:.value(L10n.text("mac.currencySettingsView.AreaMark.a7ac587ab5"),minimum * Double(monitor.configuration.displayUnits) * 0.97),yEnd:.value(L10n.text("mac.currencySettingsView.AreaMark.57ef2c45ef"),point.rate * Double(monitor.configuration.displayUnits))).foregroundStyle(LinearGradient(colors:[.red.opacity(0.2),.red.opacity(0.01)],startPoint:.top,endPoint:.bottom))
                    LineMark(x:.value(L10n.text("mac.currencySettingsView.LineMark.70d0c1b336"),point.retrievedAt),y:.value(L10n.text("mac.currencySettingsView.LineMark.57ef2c45ef"),point.rate * Double(monitor.configuration.displayUnits))).foregroundStyle(.red).lineStyle(StrokeStyle(lineWidth:1.6))
                }.chartYScale(domain:minimum * Double(monitor.configuration.displayUnits) * 0.97...maximum * Double(monitor.configuration.displayUnits) * 1.03).chartXAxis { AxisMarks(values:.stride(by:.month)) { _ in AxisValueLabel(format:.dateTime.month(.twoDigits).day()) } }.frame(minHeight:220)
                HStack(spacing:0) {
                    historyMetric(MacFXMath.formatted(minimum * Double(monitor.configuration.displayUnits),digits:monitor.configuration.rateDigits),L10n.text("mac.currencySettingsView.historyMetric.47d30e252c"))
                    Divider()
                    historyMetric(MacFXMath.formatted(maximum * Double(monitor.configuration.displayUnits),digits:monitor.configuration.rateDigits),L10n.text("mac.currencySettingsView.historyMetric.e215292fd2"))
                    Divider(); historyMetric(change,L10n.text("mac.currencySettingsView.historyMetric.3e4e456d32"))
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
    @ObservedObject private var localizationState = LocalizationController.shared
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
            Text(L10n.text("mac.currencySettingsView.body.cb986957fd")).appFont(.dialogTitle, weight: .semibold)
            HStack(spacing: MacUI.space(14)) {
                MacFXSourceImage(source: source, size: 48)
                MacImageImportControl(data: Binding(get: { source.imageData ?? Data() }, set: { source.imageData = $0.isEmpty ? nil : $0 }), cropTitle: L10n.text("mac.currencySettingsView.MacImageImportControl.629844a140"), label: source.name, identifier: "fxSourceImage")
                Spacer()
            }
            MacSettingsRow(label: L10n.text("mac.currencySettingsView.body.d8f720d148"), labelWidth: 100) {
                MacSettingsMenu(selection: $template, options: MacFXTemplate.allCases.map { ($0.title, $0) }).accessibilityIdentifier("fxTemplateMenu")
            }
            if template == .custom {
                TextField(L10n.text("mac.currencySettingsView.body.d44e9b3d3b"), text: $source.name).accessibilityIdentifier("fxSourceName")
                TextField(L10n.text("mac.currencySettingsView.body.9c258cf3d3"), text: $source.urlTemplate).accessibilityIdentifier("fxSourceURL")
                TextField(L10n.text("mac.currencySettingsView.body.cde0315ba5"), text: $source.ratePath).accessibilityIdentifier("fxSourcePath")
                TextField(L10n.text("mac.currencySettingsView.body.21c36fa5f9"), text: $source.datePath).accessibilityIdentifier("fxSourceDatePath")
                TextField(L10n.text("mac.currencySettingsView.body.69bff92570"), text: Binding(get: { source.dateTimeZoneID ?? "" }, set: { source.dateTimeZoneID = $0.isEmpty ? nil : $0 })).accessibilityIdentifier("fxSourceTimeZone")
                Text(L10n.text("mac.currencySettingsView.body.a8d6a42f38")).appFont(.caption).foregroundStyle(.secondary)
            } else {
                Text(template == .twelveData ? L10n.text("mac.currencySettingsView.body.f1130ec972") : L10n.text("mac.currencySettingsView.body.dd155b795d"))
                    .appFont(.caption).foregroundStyle(.secondary)
            }
            SecureField(template == .openExchangeRates ? L10n.text("mac.currencySettingsView.SecureField.91d1fe9a45") : L10n.text("mac.currencySettingsView.SecureField.d03bad5bcd"), text: $key).accessibilityIdentifier("fxSourceKey")
            Text(L10n.text("mac.currencySettingsView.body.6f8dba3fcd"))
                .appFont(.caption).foregroundStyle(.secondary)
            Toggle(L10n.text("mac.currencySettingsView.body.197b44d648"), isOn: $source.enabled)
            if let result { Text(result).foregroundStyle(.green).accessibilityIdentifier("fxConnectionResult") }
            if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("fxSourceError") }
            HStack {
                Button(L10n.text("mac.currencySettingsView.body.2cd0f3be87")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(busy ? L10n.text("mac.currencySettingsView.body.105a9082c3") : L10n.text("mac.currencySettingsView.body.200f465659")) { Task { await test() } }.disabled(busy).accessibilityIdentifier("fxConnectionTest")
                Spacer()
                Button(L10n.text("mac.currencySettingsView.body.a3030bf8f1")) { Task { busy=true;defer{busy=false};do { if template != .custom && key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw MacSettingsFailure.invalid(L10n.text("mac.currencySettingsView.Task.e0557bf3ba")) }; try await MacFXService.saveAsync(source, key: key); dismiss() } catch { self.error = MacLocalization.error(error) } } }.disabled(busy).accessibilityIdentifier("fxSourceSave")
            }
        }.appPadding(26).appDialog(width: 570)
        .task { template = source.provider.flatMap(MacFXTemplate.init(rawValue:)) ?? .custom; busy=true;defer{busy=false};do {key=try await MacFXSecrets.readAsync(source.id,retryAuthorization:true)}catch{self.error=error.localizedDescription} }
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
            result = L10n.format("mac.currencySettingsView.test.2708d7a304", "\(from)", "\(rate)", "\(to)")
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
