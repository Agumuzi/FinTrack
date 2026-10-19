import SwiftUI
import AppKit

struct MacFXConverterView: View {
    @ObservedObject var service: MacFXMonitor
    @ObservedObject var query: MacFXQuerySession
    var showsTools = true
    @AppStorage("v2_grouping", store: MacPreferences.defaults) private var grouping = "comma"
    private var codes: [String] {
        let selected = service.configuration.converterCurrencies.filter { MacFXCatalog.codes.contains($0) }
        guard !selected.isEmpty else { return [] }
        return MacFXCatalog.codes.contains(query.inputCurrency) && !selected.contains(query.inputCurrency) ? [query.inputCurrency] + selected : selected
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsTools {
            HStack {
                Text("点击币种卡片输入金额").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button(service.busy ? "更新中…" : "更新", systemImage: "arrow.clockwise") { Task { await service.refresh(reason: .manual) } }
                    .buttonStyle(MacSettingsButtonStyle(height: 40)).disabled(service.busy).accessibilityIdentifier("fxConverterUpdate")
            }
            }
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(codes, id: \.self) { code in
                        MacFXCurrencyAmountCard(
                            code: code, active: query.inputCurrency == code,
                            input: Binding(get: { query.inputText }, set: { query.inputText = $0 }),
                            units: service.configuration.displayUnits,
                            result: query.converter.result(code, quotes: service.quotes, units: service.configuration.displayUnits, digits: service.configuration.rateDigits, grouping: grouping),
                            missingText: query.converter.failureText(code, quotes: service.quotes, units: service.configuration.displayUnits),
                            status: query.converter.parsed().status,
                            annotation: annotation(code), details:evidence(code), select: { query.inputCurrency = code }
                        ).id(code)
                    }
                }.scrollTargetLayout().padding(.bottom, 8)
                if codes.isEmpty {
                    ContentUnavailableView("尚未选择换算币种", systemImage: "arrow.left.arrow.right", description: Text("请在货币与汇率设置中选择换算币种。"))
                }
            }.scrollPosition(id: $query.converterScrollCode, anchor: .top).accessibilityIdentifier("fxConverterScroll")
            MacFXLastUpdatedView(service:service)
        }
        .onAppear { reconcile() }
        .onChange(of: MacFXCatalog.codes + service.configuration.converterCurrencies) { _, _ in reconcile() }
        .task { await service.pageOpened() }
    }
    private func reconcile() {
        if !MacFXCatalog.codes.contains(query.inputCurrency) || codes.isEmpty { query.converter.reconcile(codes) }
    }
    private func annotation(_ code: String) -> String? {
        guard code != query.inputCurrency, let conversion = MacFXMath.resolve(from: query.inputCurrency, to: code, quotes: service.quotes) else { return nil }
        return conversion.isEstimate ? "参考估算 · 日级或混合来源／时间" : nil
    }
    private func evidence(_ code: String) -> String {
        guard let route = MacFXMath.resolve(from: query.inputCurrency, to: code, quotes: service.quotes) else { return code + "：缺少报价" }
        return code + "：" + route.legs.map { leg in
            let name = service.providerList().first { $0.id == leg.sourceID }?.name ?? "缓存源"
            return leg.pair.key + " · " + name + " · " + MacFXDates.label(leg.quoteTime)
        }.joined(separator: "\n")
    }
}

/// One editable currency; other cards contain calculated text, never another draft.
private struct MacFXCurrencyAmountCard: View {
    let code: String
    let active: Bool
    @Binding var input: String
    let units: Int
    let result: String?
    let missingText: String
    let status: MacFXConverterState.InputStatus
    let annotation: String?
    let details: String
    let select: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Button { activate() } label: {
                    HStack(spacing: 8) {
                        MacCurrencyFlag(code: code, width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(code).appFont(.section, weight: .semibold)
                            Text(MacSettingsVisual.currencyName(code)).appFont(.caption, weight: .regular).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).fixedSize(horizontal: true, vertical: false)
                    .accessibilityIdentifier("fxSelect-" + code).accessibilityValue(active ? "输入币种" : "换算结果")
                Spacer(minLength: 4)
                if active {
                    TextField("输入金额", text: $input, prompt: Text(""))
                        .textFieldStyle(.plain).appFont(.amount, weight: .semibold)
                        .multilineTextAlignment(.trailing).focused($focused).frame(minWidth: 90, maxWidth: 190, minHeight: 44)
                        .overlay(alignment: .trailing) {
                            if input.isEmpty { Text(String(units)).appFont(.amount, weight: .semibold).foregroundStyle(.secondary).allowsHitTesting(false).accessibilityHidden(true) }
                        }
                        .accessibilityHint("空输入按\(units)单位试算")
                        .accessibilityLabel(code + " 输入金额").accessibilityIdentifier("fxConverterInput")
                } else {
                    MacFXValueDisplay(value:result,placeholder:missingText,identifier:"fxResult-" + code)
                        .frame(maxWidth: 190)
                        .contentShape(Rectangle()).onTapGesture { activate() }
                        .accessibilityAddTraits(.isButton).accessibilityAction { activate() }
                        .accessibilityHint("点击后以" + code + "输入")
                    Button { if let result { MacFXCopy.text(result) } } label: {
                        Image(systemName: "doc.on.doc").frame(width: 32, height: 40).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(result == nil).accessibilityLabel("复制" + code + "结果").accessibilityIdentifier("fxCopy-" + code)
                }
            }
            if active, let message = MacFXInputMessage.text(status) {
                Text(LocalizedStringKey(message)).appFont(.caption, weight: .regular).foregroundStyle(status == .editing ? Color.secondary : .red).accessibilityIdentifier("fxInputError")
            }
            if let annotation, !active {
                Text(annotation).appFont(.caption, weight: .regular).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: active ? 72 : 64, alignment: .leading)
        .background(active ? MacUI.accent.opacity(0.12) : MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(active ? MacUI.accent.opacity(0.45) : Color.secondary.opacity(0.12)))
        .help(details)
        .contentShape(RoundedRectangle(cornerRadius: 14)).onTapGesture { activate() }
        .onChange(of: active) { _, value in if value { DispatchQueue.main.async { focused = true } } else { focused = false } }
    }
    private func activate() { select(); focused = true }
}

/// Textual states use body typography; only actual numbers use the amount role.
struct MacFXValueDisplay: View {
    var value: String?
    var placeholder: String
    var identifier: String
    var role: MacUI.TextRole = .amount
    var body: some View {
        Group {
            if let value { MacFXScrollableNumber(text:value,identifier:identifier,role:role) }
            else {
                Text(MacLocalization.value(placeholder)).appFont(.body,weight:.regular).foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing).fixedSize(horizontal:false,vertical:true)
                    .frame(maxWidth:.infinity,minHeight:40,alignment:.trailing)
                    .accessibilityLabel(MacLocalization.value(placeholder)).accessibilityValue(MacLocalization.value(placeholder)).accessibilityIdentifier(identifier)
            }
        }
    }
}

struct MacFXScrollableNumber: View {
    var text: String
    var identifier: String
    var role: MacUI.TextRole = .amount
    private var number: some View { Text(text).appFont(role,weight:.semibold).monospacedDigit().fixedSize().frame(minHeight:40) }
    var body: some View {
        ViewThatFits(in:.horizontal) {
            number
            ScrollView(.horizontal,showsIndicators:true) { number }
                .defaultScrollAnchor(.trailing).id(text).help(text + " · 金额较长，可横向滚动查看完整数值")
        }.frame(minWidth:80,maxWidth:.infinity,minHeight:40,maxHeight:40,alignment:.trailing)
            .layoutPriority(1)
            .accessibilityElement(children:.ignore).accessibilityLabel(text).accessibilityValue(text).accessibilityIdentifier(identifier)
    }
}

enum MacFXInputMessage {
    static func text(_ status: MacFXConverterState.InputStatus) -> String? {
        switch status {
        case .editing: "继续输入金额"
        case .invalid: "请输入有效的非负金额"
        case .overflow: "金额超出可换算范围"
        case .valid, .empty: nil
        }
    }
}
enum MacFXCopy {
    static func text(_ value: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string) }
}
