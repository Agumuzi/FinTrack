import SwiftUI
import Charts

struct MacFXTrendCardView: View {
    let pair: MacFXPair
    let range: MacFXHistoryRange
    @ObservedObject var service: MacFXMonitor
    @ObservedObject var history: MacFXHistoryService
    private var request: MacFXHistoryRequest? { history.request(pair: pair, range: range, monitor: service) }
    private var result: MacFXHistoryResult? { request.flatMap { history.results[$0] } }
    private var points: [MacFXHistoryPoint] { (result?.points ?? []).filter { ($0.unitRate * multiplier).isFinite && $0.unitRate * multiplier < Double.greatestFiniteMagnitude / 2 } }
    private var multiplier: Double { Double(service.configuration.displayUnits) }
    private var minY: Double { (points.map(\.unitRate).min() ?? 0) * multiplier }
    private var maxY: Double { (points.map(\.unitRate).max() ?? 1) * multiplier }
    private var padding: Double { max((maxY - minY) * 0.12, abs(maxY) * 0.001, 1e-12) }
    private var color: Color { (points.last?.unitRate ?? 0) >= (points.first?.unitRate ?? 0) ? .green : .red }
    private var yTicks: [Double] { Array(Set([minY, (minY + maxY) / 2, maxY])).sorted() }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Group {
                if points.count >= 2 {
                    Chart(Array(points.enumerated()), id: \.offset) { index, point in
                        AreaMark(x: .value("报价日", point.date), yStart: .value("基线", max(0, minY - padding)), yEnd: .value("汇率", point.unitRate * multiplier), series: .value("连续区间", segment(index)))
                            .foregroundStyle(LinearGradient(colors: [color.opacity(0.16), color.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("报价日", point.date), y: .value("汇率", point.unitRate * multiplier), series: .value("连续区间", segment(index)))
                            .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("报价日", point.date), y: .value("汇率", point.unitRate * multiplier)).foregroundStyle(color).symbolSize(8)
                    }
                    .chartYScale(domain: max(0, minY - padding)...(maxY + padding))
                    .chartYAxis { AxisMarks(position:.leading,values:yTicks) { value in
                        AxisGridLine(); AxisTick(); AxisValueLabel { if let number = value.as(Double.self) { Text(MacFXMath.formatted(number, digits: service.configuration.rateDigits, grouping: true)).appFont(.caption) } }
                    } }
                    .chartXAxis { AxisMarks(values:.automatic(desiredCount:3)) { value in
                        AxisGridLine(); AxisValueLabel(anchor: .topLeading) { if let date = value.as(Date.self) { Text(String(MacFXDates.tag(date, calendar: MacFXDates.utc).suffix(5))).appFont(.caption) } }
                    } }
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
        var text = result.completedDays < result.totalDays ? "加载 \(result.completedDays)/\(result.totalDays) · " : ""
        text += result.sourceName + (range.rawValue > 31 ? " · 采样" : "") + (result.fromCache ? " · 缓存" : "")
        if let first = points.first, let last = points.last {
            text += " · " + first.day + "～" + last.day.suffix(5)
            if points.count >= 2 { text += String(format: " · 区间变化 %+.2f%%", (last.unitRate / first.unitRate - 1) * 100) }
        }
        if result.failedDays > 0 { text += " · 缺\(result.failedDays)个日期" }
        return text
    }
    private func segment(_ index: Int) -> Int {
        guard index > 0 else { return 0 }
        let maximumGap = Double(max(1, Int(ceil(Double(range.rawValue - 1) / 30)))) * 86400 * 1.6
        return (1...index).filter { points[$0].date.timeIntervalSince(points[$0 - 1].date) > maximumGap }.count
    }
}
