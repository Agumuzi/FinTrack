import SwiftUI

struct MacFXTrendCardView: View {
    let pair: MacFXPair
    let range: MacFXHistoryRange
    @ObservedObject var service: MacFXMonitor
    @ObservedObject var history: MacFXHistoryService
    private var request: MacFXHistoryRequest? { history.request(pair: pair, range: range, monitor: service) }
    private var result: MacFXHistoryResult? { request.flatMap { history.result(for: $0) } }
    private var plot: MacFXHistoryPlot { result?.plot ?? MacFXHistoryPlot([]) }
    private var points: [MacFXHistoryPlot.Point] { plot.points }
    private var multiplier: Double { Double(service.configuration.displayUnits) }
    private var minY: Double { plot.minimum * multiplier }
    private var maxY: Double { plot.maximum * multiplier }
    private var padding: Double { max((maxY - minY) * 0.12, abs(maxY) * 0.001, 1e-12) }
    private var color: Color { (points.last?.unitRate ?? 0) >= (points.first?.unitRate ?? 0) ? .green : .red }
    private var yTicks: [Double] { Array(Set([minY, (minY + maxY) / 2, maxY])).sorted() }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Group {
                if points.count >= 2 {
                    MacFXHistoryCanvas(plot: plot, multiplier: multiplier, digits: service.configuration.rateDigits)
                    .accessibilityElement(children: .ignore).accessibilityLabel(pair.key + "历史汇率，" + summary)
                    .accessibilityIdentifier("fxHistoryChart-" + pair.key)
                } else {
                    VStack(spacing: 8) {
                        if let request, history.loading.contains(request) { ProgressView().controlSize(.small); Text("正在加载历史报价") }
                        else { Text(request == nil ? "此来源不支持历史图" : result?.error ?? "历史数据不足") }
                    }.appFont(.caption, weight: .regular).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.frame(height: 136).padding(8).background(MacOverviewStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
            if let result {
                Text(summary).appFont(.caption, weight: .regular).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8).appHelp(summary).accessibilityIdentifier("fxHistorySummary-" + pair.key)
                if let error = result.error { Text("部分历史日期未取得报价：" + error).appFont(.caption, weight: .regular).foregroundStyle(.secondary).lineLimit(2).appHelp(error) }
            }
        }.task(id: request) { if let request { await history.load(request, monitor: service) } }
    }
    private var summary: String {
        guard let result else { return "" }
        let rangeQuery = request.map { service.supportsRange($0) } ?? false
        var text = result.completedDays < result.totalDays ? (rangeQuery ? MacLocalization.value("正在加载历史报价") : "加载 \(result.completedDays)/\(result.totalDays)") + " · " : ""
        text += MacLocalization.value(result.sourceName) + (result.points.count > points.count ? " · 采样" : "") + (result.fromCache ? " · 缓存" : "")
        if let first = points.first, let last = points.last {
            text += " · " + first.day + "～" + last.day.suffix(5)
            if points.count >= 2 { text += String(format: " · 区间变化 %+.2f%%", (last.unitRate / first.unitRate - 1) * 100) }
        }
        if result.failedDays > 0 { text += rangeQuery ? " · " + MacLocalization.value("历史更新未完成") : " · 缺\(result.failedDays)个日期" }
        return text
    }
}

/// The history preview has no chart-selection gestures. Render its immutable
/// line/area snapshot directly instead of laying out a mark tree on each update.
private struct MacFXHistoryCanvas: View {
    let plot: MacFXHistoryPlot
    let multiplier: Double
    let digits: Int
    var body: some View {
        let points = plot.points
        let low = plot.minimum * multiplier, high = plot.maximum * multiplier
        let padding = max((high - low) * 0.12, abs(high) * 0.001, 1e-12)
        let bottom = max(0, low - padding), top = high + padding
        let ticks = Array(Set([low, (low + high) / 2, high])).sorted()
        let labels = ticks.map { MacFXMath.formatted($0, digits: digits, grouping: true) }
        let fontSize = MacUI.fontSize(.caption, tier: MacUI.fontTier)
        let axisWidth = min(100, max(42, Double(labels.map(\.count).max() ?? 0) * Double(fontSize) * 0.62 + 8))
        let color: Color = (points.last?.unitRate ?? 0) >= (points.first?.unitRate ?? 0) ? .green : .red
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - axisWidth - 5), height = max(1, geometry.size.height - fontSize - 10)
            let first = points.first?.date ?? .distantPast, last = points.last?.date ?? first
            let duration = max(1, last.timeIntervalSince(first))
            let extent = max(1e-12, top - bottom)
            ZStack(alignment: .topLeading) {
                Canvas(rendersAsynchronously: true) { context, _ in
                    func position(_ point: MacFXHistoryPlot.Point) -> CGPoint {
                        CGPoint(x: axisWidth + point.date.timeIntervalSince(first) / duration * width,
                                y: (top - point.unitRate * multiplier) / extent * height + 3)
                    }
                    var grid = Path()
                    for tick in ticks {
                        let y = (top - tick) / extent * height + 3
                        grid.move(to: CGPoint(x: axisWidth, y: y)); grid.addLine(to: CGPoint(x: axisWidth + width, y: y))
                    }
                    for fraction in [0.0, 0.5, 1.0] {
                        let x = axisWidth + fraction * width
                        grid.move(to: CGPoint(x: x, y: 3)); grid.addLine(to: CGPoint(x: x, y: height + 3))
                    }
                    context.stroke(grid, with: .color(.secondary.opacity(0.18)), lineWidth: 0.5)
                    for segment in Dictionary(grouping: points, by: \.segment).values {
                        guard let first = segment.first else { continue }
                        var line = Path(); line.move(to: position(first))
                        for point in segment.dropFirst() { line.addLine(to: position(point)) }
                        var area = line
                        if let last = segment.last {
                            area.addLine(to: CGPoint(x: position(last).x, y: height + 3))
                            area.addLine(to: CGPoint(x: position(first).x, y: height + 3)); area.closeSubpath()
                        }
                        context.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.16), color.opacity(0.01)]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: height)))
                        context.stroke(line, with: .color(color), lineWidth: 2)
                        for point in segment {
                            let p = position(point)
                            context.fill(Path(ellipseIn: CGRect(x: p.x - 1.6, y: p.y - 1.6, width: 3.2, height: 3.2)), with: .color(color))
                        }
                    }
                }
                ForEach(Array(ticks.enumerated()), id: \.offset) { index, tick in
                    Text(labels[index]).appFont(.caption).foregroundStyle(.secondary)
                        .frame(width: axisWidth - 7, alignment: .trailing)
                        .position(x: (axisWidth - 7) / 2, y: (top - tick) / extent * height + 3)
                }
                if let first = points.first, let last = points.last {
                    let labels = Set([0, points.count / 2, points.count - 1]).sorted().map { points[$0] }
                    ForEach(labels) { point in
                        Text(String(point.day.suffix(5))).appFont(.caption).foregroundStyle(.secondary)
                            .position(x: min(geometry.size.width - 18, max(axisWidth + 18, axisWidth + point.date.timeIntervalSince(first.date) / duration * width)), y: height + fontSize / 2 + 8)
                    }
                }
            }
        }
    }
}
