import SwiftUI
import AppKit
import Combine

nonisolated enum MacSelectionPopoverGeometry {
    static func frame(size: CGSize, pointer: CGPoint, visible: CGRect) -> CGRect {
        let inset: CGFloat = 8
        let width = min(size.width, max(1, visible.width - inset * 2))
        let height = min(size.height, max(1, visible.height - inset * 2))
        // Put the pointer just inside the top-left corner, so leaving the card
        // means leaving its actual bounds, rather than crossing an artificial gap.
        let x = min(max(pointer.x - 16, visible.minX + inset), visible.maxX - width - inset)
        let y = min(max(pointer.y - height + 16, visible.minY + inset), visible.maxY - height - inset)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

nonisolated enum MacSelectionCurrencySearch {
    static let all = Locale.Currency.isoCurrencies.map(\.identifier).sorted()
    static func matches(_ text: String, candidates: [String]) -> [String] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !query.isEmpty, query.count <= 3, query.unicodeScalars.allSatisfy({ (65...90).contains(Int($0.value)) }) else { return [] }
        return candidates.filter { $0.hasPrefix(query) }

    }
}

@MainActor
final class MacSelectionSession: ObservableObject {
    struct Output {
        var result: String
        var original: String
        var evidence: String
        var copied: Bool
        var cached: Bool
        var sourceLabel: String
    }
    enum Phase { case choose, loading, result(Output), failure(String) }
    @Published private(set) var phase: Phase = .choose
    @Published var query = ""
    @Published var amountIndex: Int?
    @Published var source: String?
    let parsed: MacSelectedAmountParser.Parsed
    let target: String
    let candidates: [String]
    var phaseChanged: (() -> Void)?
    private let monitor: MacFXMonitor
    private let copy: (String) -> Bool
    private var task: Task<Void, Never>?
    private var generation = 0
    private var ended = false

    init(parsed: MacSelectedAmountParser.Parsed, target: String, monitor: MacFXMonitor, copy: @escaping (String) -> Bool) {
        self.parsed = parsed; self.target = target; self.monitor = monitor; self.copy = copy
        candidates = parsed.currencies.isEmpty ? MacSelectionCurrencySearch.all : parsed.currencies
        amountIndex = parsed.amounts.count == 1 ? 0 : nil
        source = parsed.currencies.count == 1 ? parsed.currencies[0] : nil
    }
    var typedCurrency: String? {
        let code = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return code.count == 3 ? MacSelectionCurrencySearch.matches(code, candidates: candidates).first : nil
    }
    var suggested: [String] { monitor.configuration.converterCurrencies.filter { candidates.contains($0) && monitor.currencyCodes().contains($0) } }
    var amountText: String { amountIndex.map { NSDecimalNumber(decimal: parsed.amounts[$0]).stringValue } ?? "请选择金额解释" }
    func selectCurrency(_ code: String) { guard candidates.contains(code) else { return }; source = code; begin() }
    func chooseAmount(_ index: Int) { guard parsed.amounts.indices.contains(index) else { return }; amountIndex = index; begin() }
    func continueChoice() { if let code = typedCurrency { source = code }; begin() }
    func cancel() { ended = true; generation += 1; task?.cancel(); task = nil }
    private func set(_ value: Phase) { guard !ended else { return }; phase = value; phaseChanged?() }
    func begin() {
        guard !ended, let source, let index = amountIndex, parsed.amounts.indices.contains(index) else { return }
        task?.cancel(); generation += 1; let expected = generation
        if let route = monitor.selectionRoute(from: source, to: target) { finish(route, source: source, index: index, generation: expected, cached: source != target); return }
        set(.loading)
        task = Task { [weak self] in
            guard let self else { return }
            let route = await monitor.loadSelectionRoute(from: source, to: target)
            guard !Task.isCancelled, !ended, generation == expected else { return }
            if let route { finish(route, source: source, index: index, generation: expected, cached: false) }
            else { set(.failure("没有可用汇率，请检查网络或数据源。")) }
        }
    }
    private func finish(_ route: MacFXMath.Conversion, source: String, index: Int, generation expected: Int, cached: Bool) {
        guard !ended, generation == expected else { return }
        let value = NSDecimalNumber(decimal: parsed.amounts[index]).multiplying(by: NSDecimalNumber(value: route.unitRate))
        guard value != .notANumber, value.doubleValue.isFinite else { set(.failure("金额超出可换算范围")); return }
        let text = MacFXMath.formatted(value.doubleValue, digits: monitor.configuration.rateDigits, grouping: false) + " " + target
        let detail = route.legs.isEmpty ? "同币种 · 1:1" : route.legs.map { leg in (monitor.providerList().first(where: { $0.id == leg.sourceID })?.name ?? leg.sourceID) + " · " + MacFXDates.label(leg.quoteTime) }.joined(separator: " · ")
        let fallback = !["free", "auto"].contains(monitor.configuration.sourcePolicy) && route.legs.contains { MacFXSourceScope.isSystem($0.sourceID) }
        let label = fallback ? "系统备用" : route.legs.first.map { leg in monitor.providerList().first(where: { $0.id == leg.sourceID })?.name ?? "已保存来源" } ?? "同币种"
        let copied = copy(text)
        set(.result(Output(result: text, original: amountText + " " + source, evidence: detail, copied: copied, cached: cached, sourceLabel: label)))
    }
}

struct MacSelectionPopoverView: View {
    @ObservedObject var session: MacSelectionSession
    let dismiss: () -> Void
    @FocusState private var editing: Bool
    var body: some View {
        Group {
            switch session.phase {
            case .choose: choice
            case .loading:
                HStack(spacing: 16) { ProgressView().controlSize(.small); VStack(alignment: .leading, spacing: 7) { Text("正在获取汇率").font(.headline); Text(session.amountText + " → " + session.target).foregroundStyle(.secondary) }; Spacer() }.padding(22)
            case .failure(let message):
                HStack(spacing: 14) { Image(systemName: "exclamationmark.circle").font(.title2).foregroundStyle(.orange); Text(message).font(.body).fixedSize(horizontal: false, vertical: true) }.padding(22)
            case .result(let output):
                HStack(spacing: 16) {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 23, weight: .semibold)).foregroundStyle(MacUI.accent).frame(width: 48, height: 48).background(MacUI.accent.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 6) {
                        Text((output.copied ? "换算结果 · 已复制" : "换算结果 · 未复制") + (output.cached ? " · 缓存" : "")).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                        Text(output.result).font(.system(size: 27, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5).accessibilityIdentifier("selectionConversionResult")
                        Text(output.original + " · " + output.sourceLabel).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }.padding(20).appHelp(output.evidence)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    private var choice: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("检测到金额：" + session.amountText).font(.system(size: 19, weight: .semibold))
            if session.parsed.amounts.count > 1 {
                HStack { ForEach(session.parsed.amounts.indices, id: \.self) { index in Button(NSDecimalNumber(decimal: session.parsed.amounts[index]).stringValue) { session.chooseAmount(index) }.buttonStyle(.bordered).tint(session.amountIndex == index ? MacUI.accent : .secondary) } }
            }
            Text(session.parsed.currencies.isEmpty ? "输入原始货币代码，结果将换算为 " + session.target : "输入原始货币代码，结果将换算为 " + session.target).font(.system(size: 13)).foregroundStyle(.secondary)
            TextField("三位货币代码", text: $session.query).textFieldStyle(.roundedBorder).focused($editing).onSubmit { session.continueChoice() }.accessibilityIdentifier("selectionCurrencyInput")
            if !session.suggested.isEmpty {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(session.suggested, id: \.self) { code in
                            Button(code) { session.selectCurrency(code) }.buttonStyle(.bordered).frame(maxWidth: .infinity).accessibilityIdentifier("selectionCurrency-" + code)
                        }
                    }
                }.frame(height: min(120, CGFloat((session.suggested.count + 5) / 6) * 34))
            }
            HStack { Button("取消", action: dismiss).keyboardShortcut(.cancelAction); Spacer(); Button("继续") { session.continueChoice() }.buttonStyle(.borderedProminent).tint(MacUI.accent).disabled(session.amountIndex == nil || (session.source == nil && session.typedCurrency == nil)).accessibilityIdentifier("selectionCurrencyContinue") }
        }.padding(20).onAppear { editing = true }
    }
}

final class MacSelectionFloatingPanel: NSPanel {
    var acceptsKeyboard = false
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) } }
}

final class MacSelectionPopoverBackground: NSVisualEffectView {
    var onExit: (() -> Void)?
    private var area: NSTrackingArea?
    override func updateTrackingAreas() {
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self, userInfo: nil)
        addTrackingArea(next); area = next; super.updateTrackingAreas()
    }
    override func mouseExited(with event: NSEvent) { onExit?() }
}
