import SwiftUI

struct MacFXRateCard: View {
    @ObservedObject private var localizationState = LocalizationController.shared
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
    private var comparisonCaption: String {
        guard let change = comparison.change else { return "" }
        if !service.configuration.automatic, let current = quote,
           case .day(let end, _) = current.quoteTime, case .day(let start, _) = change.baseline.quoteTime {
            return String(format: MacLocalization.value(L10n.text("mac.fXRateCard.comparisonCaption.3c78cbef27")), start, end)
        }
        return MacLocalization.value(change.caption)
    }
    private var valueText: String { quote.map { MacFXMath.formatted($0.unitRate * Double(units), digits: digits, grouping: grouping != "none", groupingSeparator: grouping == "space" ? " " : ",") } ?? "—" }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { title; Spacer(minLength: 4); value.fixedSize(horizontal: true, vertical: false) }
                VStack(alignment: .leading, spacing: 2) { title; MacFXValueDisplay(value:quote == nil ? nil : valueText,placeholder:L10n.text("mac.fXRateCard.MacFXValueDisplay.87fdce8be2"),identifier:"fxRate-" + pair.key) }
            }
            HStack(alignment: .top, spacing: 6) {
                Text(MacSettingsVisual.currencyName(pair.base) + " / " + MacSettingsVisual.currencyName(pair.quote) + " · \(units)\(MacSettingsVisual.symbol(pair.base)) → \(MacSettingsVisual.symbol(pair.quote))")
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
                                Text(LocalizedStringKey(item.title)).appFont(.caption, weight: .medium).frame(maxWidth: .infinity, minHeight: 40).contentShape(Rectangle())
                                    .background(range == item ? MacUI.accent.opacity(0.15) : .clear, in: Capsule())
                            }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("fxRange-\(item.rawValue)-" + pair.key).accessibilityValue(range == item ? L10n.text("mac.fXRateCard.ForEach.a737fd72b0") : L10n.text("mac.fXRateCard.ForEach.0e0c21de69"))
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
                HStack(spacing: 4) { MacCurrencyFlag(code: pair.base, width: 18); Text(pair.base); Text("/").foregroundStyle(.secondary); MacCurrencyFlag(code: pair.quote, width: 18); Text(pair.quote) }.appFont(.section, weight: .semibold).fixedSize()
                Image(systemName: expanded ? "chevron.up" : "chevron.down").appFont(.caption, weight: .semibold).frame(width: 26, height: 40)
            }.contentShape(Rectangle())
        }.buttonStyle(MacInteractiveButtonStyle()).accessibilityLabel(pair.key + (expanded ? L10n.text("mac.fXRateCard.title.0ae7312510") : L10n.text("mac.fXRateCard.title.4bf0fb2140")))
            .accessibilityIdentifier("fxToggle-" + pair.key).accessibilityValue(expanded ? L10n.text("mac.fXRateCard.title.df647b73b9") : L10n.text("mac.fXRateCard.title.e64447db76"))
    }
    @ViewBuilder private var value: some View {
        if quote != nil {
            Text(valueText).appFont(.amount,weight:.bold).monospacedDigit().lineLimit(1)
                .accessibilityIdentifier("fxRate-" + pair.key).accessibilityValue(valueText + " " + pair.quote)
        } else {
            Text(L10n.text("mac.fXRateCard.value.87fdce8be2")).appFont(.body,weight:.regular).foregroundStyle(.secondary)
                .accessibilityIdentifier("fxRate-" + pair.key).accessibilityValue(L10n.text("mac.fXRateCard.value.87fdce8be2"))
        }
    }
    @ViewBuilder private var changeChip: some View {
        if let change = comparison.change {
            Text((change.difference > 0 ? "+" : "") + MacFXMath.formatted(change.difference * Double(units), digits: digits))
                .foregroundStyle(change.difference < 0 ? Color.red : .green)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background((change.difference < 0 ? Color.red : .green).opacity(0.10), in: Capsule())
                .appHelp(comparisonCaption + String(format: " · %+.2f%%", change.percent))
                .accessibilityLabel(comparisonCaption + String(format: " · %+.2f%%", change.percent))
                .appFont(.caption, weight: .semibold).fixedSize()
        } else {
            Text(L10n.text("mac.fXRateCard.changeChip.580011fdb4")).appFont(.caption, weight: .regular).foregroundStyle(.secondary).appHelp(MacLocalization.value(comparison.reason)).fixedSize()
        }
    }
    private var modes: some View {
        HStack(spacing: 4) {
            modeButton(.history, title: L10n.text("mac.fXRateCard.modeButton.b0385cfe4b"), symbol: "chart.line.uptrend.xyaxis")
            modeButton(.converter, title: L10n.text("mac.fXRateCard.modeButton.d9c792dfca"), symbol: "arrow.left.arrow.right")
        }.padding(3).background(MacOverviewStyle.filters, in: RoundedRectangle(cornerRadius: 10))
    }
    private func modeButton(_ item: MacFXCardMode, title: String, symbol: String) -> some View {
        Button {
            query.cardModes[pair.key] = item
            if item == .converter { DispatchQueue.main.async { focusedCode = input.activeCode } }
        } label: {
            Label(title, systemImage: symbol).appFont(.label, weight: .medium).frame(maxWidth: .infinity, minHeight: 34).contentShape(Rectangle())
                .background(mode == item ? MacOverviewStyle.card : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("fxCardMode-" + item.rawValue + "-" + pair.key).accessibilityValue(mode == item ? L10n.text("mac.fXRateCard.modeButton.a737fd72b0") : L10n.text("mac.fXRateCard.modeButton.0e0c21de69"))
    }
    private func amountField(_ code: String) -> some View {
        let active = input.activeCode == code
        let result = input.result(code, quotes: quote.map { [$0] } ?? [], units: units, digits: digits, grouping: grouping)
        let missing = input.failureText(code, quotes: quote.map { [$0] } ?? [], units: units)
        return VStack(alignment: .leading, spacing: 4) {
            Button { activate(code) } label: {
                HStack { Text(code); Spacer(); if active { Image(systemName: "pencil") } }
                    .appFont(.caption, weight: .medium).foregroundStyle(.secondary).frame(minHeight: 26).contentShape(Rectangle())
            }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("fxCardSelect-" + code + "-" + pair.key)
            if active {
                TextField(L10n.text("mac.fXRateCard.amountField.ad727176fc"), text: Binding(get: { input.inputText }, set: { query.editCard($0, pair: pair) }), prompt: Text(""))
                    .textFieldStyle(.plain).appFont(.section, weight: .semibold).multilineTextAlignment(.trailing)
                    .focused($focusedCode, equals: code).frame(minHeight: 40)
                    .overlay(alignment: .trailing) {
                        if input.inputText.isEmpty { Text(String(units)).appFont(.section, weight: .semibold).foregroundStyle(.secondary).allowsHitTesting(false).accessibilityHidden(true) }
                    }
                    .accessibilityHint(L10n.format("mac.fXRateCard.amountField.7a4ad86768", "\(units)"))
                    .accessibilityLabel(code + L10n.text("mac.fXRateCard.amountField.1e4111ab37")).accessibilityIdentifier("fxCardInput-" + code + "-" + pair.key)
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
            Text(quote.map { MacDateDisplay.string($0.retrievedAt) + " " + MacDisplayPreferences.time($0.retrievedAt) + " · " + service.sourceName($0).replacingOccurrences(of: "自定义 · ", with: "") + (service.isCached(pair) ? L10n.text("mac.fXRateCard.footer.a6c349f419") : "") } ?? L10n.text("mac.fXRateCard.footer.87fdce8be2"))
                .appFont(.caption, weight: .regular).foregroundStyle(.secondary).lineLimit(2).appHelp(quote.map { L10n.text("mac.fXRateCard.footer.dfa4eed218") + MacFXDates.label($0.quoteTime) + L10n.text("mac.fXRateCard.footer.dfdd6c7340") + MacDateDisplay.string($0.retrievedAt) + " " + MacDisplayPreferences.time($0.retrievedAt) } ?? L10n.text("mac.fXRateCard.footer.87fdce8be2"))
            Spacer(minLength: 0)
            Menu {
                Button(L10n.text("mac.fXRateCard.Menu.66239df899")) { MacFXCopy.text(pair.key + " " + valueText) }.disabled(quote == nil)
                Button(L10n.text("mac.fXRateCard.Menu.f853a70b12")) { move(-1) }; Button(L10n.text("mac.fXRateCard.Menu.e75e8b4e5c")) { move(1) }
                Button(L10n.text("mac.fXRateCard.Menu.975ce213c6"), role: .destructive) { MacFXApplication.shared.update { $0.watchedPairs.removeAll { $0 == pair } } }
            } label: { Image(systemName: "ellipsis").frame(width: 32, height: 40).contentShape(Rectangle()) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel(pair.key + L10n.text("mac.fXRateCard.footer.38844b135c"))
        }
    }
    private var evidence: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let quote {
                Text(L10n.text("mac.fXRateCard.evidence.609b04b18b") + String(quote.unitRate)).textSelection(.enabled)
                Text(L10n.text("mac.fXRateCard.evidence.6181ed6f97") + service.sourceName(quote))
                Text(MacFXDates.label(quote.quoteTime))
                Text(L10n.text("mac.fXRateCard.evidence.c00d2378a0") + MacDisplayPreferences.time(quote.retrievedAt))
                if let change = comparison.change {
                    Text(comparisonCaption + String(format: " · %+.2f%%", change.percent)); Text(L10n.text("mac.fXRateCard.evidence.486893f002") + MacFXDates.label(change.baseline.quoteTime))
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
