import SwiftUI

struct MacFXRateCard: View {
    let pair: MacFXPair
    @ObservedObject var service: MacFXMonitor
    @ObservedObject var query: MacFXQuerySession
    @ObservedObject var history: MacFXHistoryService
    @AppStorage("v2_grouping", store: MacPreferences.defaults) private var grouping = "comma"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingEvidence = false
    @FocusState private var focusedCode: String?
    private var quote: MacFXEvidenceQuote? { service.quote(pair) }
    private var units: Int { service.configuration.displayUnits }
    private var digits: Int { service.configuration.rateDigits }
    private var expanded: Bool { query.expandedPair == pair.key }
    private var mode: MacFXCardMode { query.cardModes[pair.key] ?? .history }
    private var range: MacFXHistoryRange { query.cardRanges[pair.key] ?? .month }
    private var input: MacFXConverterState { query.cardInput(pair) }
    private var comparison: MacFXComparison { service.comparison(pair) }
    private var valueText: String { quote.map { MacFXMath.formatted($0.unitRate * Double(units), digits: digits, grouping: grouping != "none", groupingSeparator: grouping == "space" ? " " : ",") } ?? "—" }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { title; Spacer(minLength: 4); value.fixedSize(horizontal: true, vertical: false) }
                VStack(alignment: .leading, spacing: 2) { title; MacFXValueDisplay(value:quote == nil ? nil : valueText,placeholder:"暂无报价",identifier:"fxRate-" + pair.key) }
            }
            HStack(alignment: .top, spacing: 6) {
                Text(MacSettingsVisual.currencyName(pair.base) + " / " + MacSettingsVisual.currencyName(pair.quote) + " · \(units) \(pair.base) → \(pair.quote)")
                    .appFont(.caption, weight: .regular).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                changeChip
            }
            if expanded {
                modes
                if mode == .history {
                    MacFXTrendCardView(pair: pair, range: range, service: service, history: history)
                    HStack(spacing: 3) {
                        ForEach(MacFXHistoryRange.allCases) { item in
                            Button { query.cardRanges[pair.key] = item } label: {
                                Text(LocalizedStringKey(item.title)).appFont(.caption, weight: .medium).frame(maxWidth: .infinity, minHeight: 40)
                                    .background(range == item ? MacUI.accent.opacity(0.15) : .clear, in: Capsule())
                            }.buttonStyle(.plain).accessibilityIdentifier("fxRange-\(item.rawValue)-" + pair.key).accessibilityValue(range == item ? "已选中" : "未选中")
                        }
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { amountField(pair.base).frame(minWidth: 125); Text("=").appFont(.body).foregroundStyle(.secondary); amountField(pair.quote).frame(minWidth: 125) }
                        VStack(spacing: 8) { amountField(pair.base); amountField(pair.quote) }
                    }.padding(.vertical, 4)
                }
            }
            footer
            if expanded {
                DisclosureGroup("报价说明", isExpanded: $showingEvidence) { evidence.padding(.top, 6) }
                    .appFont(.caption, weight: .regular).accessibilityIdentifier("fxRateDetails-" + pair.key)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(expanded ? MacUI.accent.opacity(0.4) : Color.secondary.opacity(0.12)))
            .contentShape(RoundedRectangle(cornerRadius: 15))
            .onTapGesture { if !expanded { toggle() } }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: expanded)
    }
    private var title: some View {
        Button { toggle() } label: {
            HStack(spacing: 4) {
                Text(pair.key).appFont(.section, weight: .semibold).fixedSize()
                Image(systemName: expanded ? "chevron.up" : "chevron.down").appFont(.caption, weight: .semibold).frame(width: 26, height: 40)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(pair.key + (expanded ? "收起详情" : "展开详情"))
            .accessibilityIdentifier("fxToggle-" + pair.key).accessibilityValue(expanded ? "已展开" : "已收起")
    }
    @ViewBuilder private var value: some View {
        if quote != nil {
            Text(valueText).appFont(.amount,weight:.semibold).monospacedDigit().lineLimit(1)
                .accessibilityIdentifier("fxRate-" + pair.key).accessibilityValue(valueText + " " + pair.quote)
        } else {
            Text("暂无报价").appFont(.body,weight:.regular).foregroundStyle(.secondary)
                .accessibilityIdentifier("fxRate-" + pair.key).accessibilityValue("暂无报价")
        }
    }
    @ViewBuilder private var changeChip: some View {
        if let change = comparison.change {
            Text((change.difference > 0 ? "+" : "") + MacFXMath.formatted(change.difference * Double(units), digits: digits))
                .foregroundStyle(change.difference < 0 ? Color.red : .green)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background((change.difference < 0 ? Color.red : .green).opacity(0.10), in: Capsule())
                .help(change.caption + String(format: " · %+.2f%%", change.percent))
                .accessibilityLabel(change.caption + String(format: " · %+.2f%%", change.percent))
                .appFont(.caption, weight: .semibold).fixedSize()
        } else {
            Text("暂无可比数据").appFont(.caption, weight: .regular).foregroundStyle(.secondary).help(comparison.reason).fixedSize()
        }
    }
    private var modes: some View {
        HStack(spacing: 4) {
            modeButton(.history, title: "历史", symbol: "chart.line.uptrend.xyaxis")
            modeButton(.converter, title: "换算", symbol: "arrow.left.arrow.right")
        }.padding(3).background(MacOverviewStyle.filters, in: RoundedRectangle(cornerRadius: 10))
    }
    private func modeButton(_ item: MacFXCardMode, title: String, symbol: String) -> some View {
        Button {
            query.cardModes[pair.key] = item
            if item == .converter { DispatchQueue.main.async { focusedCode = input.activeCode } }
        } label: {
            Label(title, systemImage: symbol).appFont(.label, weight: .medium).frame(maxWidth: .infinity, minHeight: 34)
                .background(mode == item ? MacOverviewStyle.card : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).accessibilityIdentifier("fxCardMode-" + item.rawValue + "-" + pair.key).accessibilityValue(mode == item ? "已选中" : "未选中")
    }
    private func amountField(_ code: String) -> some View {
        let active = input.activeCode == code
        let result = input.result(code, quotes: quote.map { [$0] } ?? [], units: units, digits: digits, grouping: grouping)
        let missing = input.failureText(code, quotes: quote.map { [$0] } ?? [], units: units)
        return VStack(alignment: .leading, spacing: 4) {
            Button { activate(code) } label: {
                HStack { Text(code); Spacer(); if active { Image(systemName: "pencil") } }
                    .appFont(.caption, weight: .medium).foregroundStyle(.secondary).frame(minHeight: 26).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("fxCardSelect-" + code + "-" + pair.key)
            if active {
                TextField("输入金额", text: Binding(get: { input.inputText }, set: { query.editCard($0, pair: pair) }), prompt: Text(""))
                    .textFieldStyle(.plain).appFont(.section, weight: .semibold).multilineTextAlignment(.trailing)
                    .focused($focusedCode, equals: code).frame(minHeight: 40)
                    .overlay(alignment: .trailing) {
                        if input.inputText.isEmpty { Text(String(units)).appFont(.section, weight: .semibold).foregroundStyle(.secondary).allowsHitTesting(false).accessibilityHidden(true) }
                    }
                    .accessibilityHint("空输入按\(units)单位试算")
                    .accessibilityLabel(code + " 输入金额").accessibilityIdentifier("fxCardInput-" + code + "-" + pair.key)
            } else {
                MacFXValueDisplay(value:result,placeholder:missing,identifier:"fxCardResult-" + code + "-" + pair.key,role:.section)
                    .contentShape(Rectangle()).onTapGesture { activate(code) }
                    .accessibilityAddTraits(.isButton).accessibilityAction { activate(code) }
            }
            if active, let message = MacFXInputMessage.text(input.parsed().status) { Text(LocalizedStringKey(message)).appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
        }.padding(10).frame(maxWidth: .infinity)
            .background(active ? MacUI.accent.opacity(0.1) : MacOverviewStyle.filters, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active ? MacUI.accent.opacity(0.35) : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 10)).onTapGesture { activate(code) }
    }
    private func activate(_ code: String) { query.selectCardCurrency(code, pair: pair); focusedCode = code }
    private func toggle() { query.expandedPair = expanded ? nil : pair.key }
    private var footer: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(quote.map { MacFXDates.label($0.quoteTime) + " · " + service.sourceName($0) + (service.isCached(pair) ? " · 缓存" : "") } ?? "暂无报价")
                .appFont(.caption, weight: .regular).foregroundStyle(.secondary).lineLimit(expanded ? 3 : 2)
            Spacer(minLength: 0)
            Menu {
                Button("复制汇率") { MacFXCopy.text(pair.key + " " + valueText) }.disabled(quote == nil)
                Button("上移") { move(-1) }; Button("下移") { move(1) }
                Button("移除关注", role: .destructive) { MacFXApplication.shared.update { $0.watchedPairs.removeAll { $0 == pair } } }
            } label: { Image(systemName: "ellipsis").frame(width: 32, height: 40).contentShape(Rectangle()) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel(pair.key + "更多")
        }
    }
    private var evidence: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let quote {
                Text("每1单位：" + String(quote.unitRate)).textSelection(.enabled)
                Text("来源：" + service.sourceName(quote))
                Text(MacFXDates.label(quote.quoteTime))
                Text("获取时间：" + MacDisplayPreferences.time(quote.retrievedAt))
                if let change = comparison.change {
                    Text(change.caption + String(format: " · %+.2f%%", change.percent)); Text("基准：" + MacFXDates.label(change.baseline.quoteTime))
                } else { Text(comparison.reason) }
                ForEach(Array(quote.legs.enumerated()), id: \.offset) { _, leg in Text(leg.pair.key + " · " + MacFXDates.label(leg.quoteTime)) }
            }
            if let error = service.errors[pair] { Text(error).foregroundStyle(.red) }
            if let warning = service.warnings[pair] { Text(warning).foregroundStyle(.orange) }
        }.appFont(.caption, weight: .regular).fixedSize(horizontal: false, vertical: true)
    }
    private func move(_ distance: Int) {
        MacFXApplication.shared.update { config in
            guard let index = config.watchedPairs.firstIndex(of: pair), config.watchedPairs.indices.contains(index + distance) else { return }
            config.watchedPairs.swapAt(index, index + distance)
        }
    }
}
