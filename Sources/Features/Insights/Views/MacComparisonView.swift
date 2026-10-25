import SwiftUI
import Charts

struct MacComparisonView: View {
    let transactions: [Transaction]
    let currency: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("期间对比").appFont(.dialogTitle, weight: .semibold); Spacer(); Button("完成") { dismiss() } }
            ScrollView { MacPeriodComparisonDashboard(transactions: transactions, currency: currency) }
        }.padding(24).appPanel(width: 900, height: 720)
    }
}

struct MacPeriodComparisonDashboard: View {
    var transactions: [Transaction]
    var currency: String
    @State private var mode = "同月跨年"
    @State private var reference = Date()
    @State private var currentYear = Calendar.current.component(.year, from: Date())
    @State private var previousYear = Calendar.current.component(.year, from: Date()) - 1
    @State private var customStart = Calendar.current.dateInterval(of: .month, for: Date())!.start
    @State private var customEnd = Date()
    @State private var previousStart = Calendar.current.date(byAdding: .year, value: -1, to: Calendar.current.dateInterval(of: .month, for: Date())!.start)!
    @State private var previousEnd = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
    @State private var flow = "支出"
    private var calendar: Calendar { MacDisplayPreferences.calendar }
    private var years: [Int] {
        let thisYear = calendar.component(.year, from: Date())
        let first = transactions.map { calendar.component(.year, from: $0.date) }.min() ?? thisYear - 10
        return Array((min(first, thisYear - 10)...max(thisYear + 1, max(currentYear, previousYear))).reversed())
    }
    private var ranges: (DateInterval, DateInterval)? {
        if mode == "自选期间" {
            let a = calendar.startOfDay(for: customStart), b = calendar.startOfDay(for: previousStart)
            let ae = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEnd))!
            let be = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: previousEnd))!
            guard ae > a, be > b else { return nil }
            return (DateInterval(start: a, end: ae), DateInterval(start: b, end: be))
        }
        if mode == "年度对比" {
            let a = calendar.date(from: DateComponents(year: currentYear, month: 1, day: 1))!
            let b = calendar.date(from: DateComponents(year: previousYear, month: 1, day: 1))!
            return (calendar.dateInterval(of: .year, for: a)!, calendar.dateInterval(of: .year, for: b)!)
        }
        let year = calendar.component(.year, from: reference), month = calendar.component(.month, from: reference)
        let b = calendar.date(from: DateComponents(year: previousYear, month: month, day: 1))!
        let a = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        return (calendar.dateInterval(of: .month, for: a)!, calendar.dateInterval(of: .month, for: b)!)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            card {
                MacSettingsSegments(selection: $mode, options: ["同月跨年", "年度对比", "自选期间"])
                if mode == "自选期间" {
                    dateRange("期间 A", start: $customStart, end: $customEnd, prefix: "comparisonA")
                    dateRange("期间 B", start: $previousStart, end: $previousEnd, prefix: "comparisonB")
                } else {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("期间 A").appFont(.caption).foregroundStyle(.secondary)
                            if mode == "同月跨年" { MacSettingsDateButton(date: $reference, monthOnly: true, identifier: "comparisonMonth") }
                            else { yearMenu($currentYear, id: "comparisonCurrentYear") }
                        }.frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(mode == "同月跨年" ? "期间 B · 相同月份" : "期间 B").appFont(.caption).foregroundStyle(.secondary)
                            yearMenu($previousYear, id: "comparisonPreviousYear")
                        }.frame(maxWidth: .infinity)
                    }
                }
                if let (a, b) = ranges {
                    Text("A  " + rangeLabel(a) + "    /    B  " + rangeLabel(b)).appFont(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("comparisonRangeSummary")
                    Text("按所选完整期间汇总已记录账目；进行中的月份或年份可能尚未记全。").appFont(.caption).foregroundStyle(.secondary)
                } else { Text("开始日期不能晚于结束日期。").foregroundStyle(.red) }
            }
            if let (a, b) = ranges {
                let monthly = mode == "年度对比" || max(a.duration, b.duration) > 90 * 86400
                let snapshot = MacPeriodComparison.snapshot(rows: transactions, currency: currency, current: a, previous: b, flow: flow == "支出" ? .expense : .income, monthly: monthly, calendar: calendar)
                MacAdaptiveEqualCardLayout {
                    metric("收入", current: snapshot.current.income, previous: snapshot.previous.income, color: MacOverviewStyle.income)
                    metric("支出", current: snapshot.current.expense, previous: snapshot.previous.expense, color: MacOverviewStyle.expense)
                    metric("净额", current: snapshot.current.net, previous: snapshot.previous.net, color: MacSettingsVisual.accent)
                }
                Text("期间 A：\(snapshot.currentRows.count) 笔账目 · 期间 B：\(snapshot.previousRows.count) 笔账目")
                    .appFont(.caption).foregroundStyle(.secondary).accessibilityIdentifier("insightsTransactionCount")
                if snapshot.currentRows.isEmpty || snapshot.previousRows.isEmpty {
                    Label(snapshot.currentRows.isEmpty && snapshot.previousRows.isEmpty ? "两个期间均无账目" : (snapshot.currentRows.isEmpty ? "期间 A 无账目，金额显示为 0" : "期间 B 无账目，金额显示为 0"), systemImage: "info.circle")
                        .appFont(.caption).foregroundStyle(.secondary).accessibilityIdentifier("comparisonEmptyNotice")
                }
                card {
                    ViewThatFits {
                        HStack { Text("收支趋势").appFont(.section, weight: .semibold); Spacer(); flowControl.frame(width: 180) }
                        VStack(alignment: .leading) { Text("收支趋势").appFont(.section, weight: .semibold); flowControl }
                    }
                    Chart(snapshot.points) { point in
                        if let amount = point.current {
                            BarMark(x: .value("序号", String(point.index)), y: .value("金额", amount))
                                .foregroundStyle(by: .value("期间", "期间 A")).position(by: .value("期间", "期间 A"))
                        }
                        if let amount = point.previous {
                            BarMark(x: .value("序号", String(point.index)), y: .value("金额", amount))
                                .foregroundStyle(by: .value("期间", "期间 B")).position(by: .value("期间", "期间 B"))
                        }
                    }.chartForegroundStyleScale(["期间 A": MacSettingsVisual.accent, "期间 B": Color.blue.opacity(0.6)])
                        .chartXAxis {
                            let stride = max(1, Int(ceil(Double(snapshot.points.count) / Double(monthly ? 12 : 8))))
                            let labels = snapshot.points.filter { ($0.index - 1) % stride == 0 || $0.index == snapshot.points.count }.map { String($0.index) }
                            AxisMarks(values: labels) { value in
                                AxisGridLine(); AxisValueLabel { if let n = value.as(String.self) { Text(n + (monthly ? "月" : "日")) } }
                            }
                        }
                        .frame(height: 220).accessibilityIdentifier("periodComparisonChart")
                    Text("横轴按期间内的第几" + (monthly ? "个月" : "天") + "对齐；超出较短期间的部分不填 0。").appFont(.caption).foregroundStyle(.secondary)
                }
                card {
                    Text(flow + "分类对比").appFont(.section, weight: .semibold)
                    HStack { Text("分类"); Spacer(); column("期间 A"); column("期间 B"); column("差额 A − B") }
                        .appFont(.caption).foregroundStyle(.secondary)
                    if snapshot.categories.isEmpty { Text("所选期间没有" + flow + "记录").foregroundStyle(.secondary) }
                    ForEach(snapshot.categories) { row in
                        Divider()
                        HStack {
                            Text(MacOverviewStyle.category(row.id)).appFont(.body).frame(maxWidth: .infinity, alignment: .leading)
                            column(money(row.current)); column(money(row.previous)); column(signed(row.delta))
                        }.appFont(.caption).monospacedDigit()
                    }
                }.accessibilityIdentifier("expenseCategoryChart")
            }
        }.buttonStyle(MacSettingsButtonStyle())
    }
    private var flowControl: some View { MacSettingsSegments(selection: $flow, options: ["支出", "收入"]) }
    private func yearMenu(_ year: Binding<Int>, id: String) -> some View {
        MacSettingsMenu(selection: year, options: years.map { (String($0) + "年", $0) }).accessibilityIdentifier(id)
    }
    private func dateRange(_ title: String, start: Binding<Date>, end: Binding<Date>, prefix: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).appFont(.caption).foregroundStyle(.secondary)
            HStack { MacSettingsDateButton(date: start, identifier: prefix + "Start"); Text("至").foregroundStyle(.secondary); MacSettingsDateButton(date: end, identifier: prefix + "End") }
        }
    }
    private func rangeLabel(_ interval: DateInterval) -> String {
        MacDateDisplay.string(interval.start) + " – " + MacDateDisplay.string(interval.end.addingTimeInterval(-1))
    }
    private func money(_ value: Double) -> String { MacDisplayPreferences.money(value) }
    private func signed(_ value: Double) -> String { (value > 0 ? "+" : "") + money(value) }
    private func column(_ text: String) -> some View { Text(text).frame(width: 105, alignment: .trailing).fixedSize(horizontal: false, vertical: true) }
    private func metric(_ title: String, current: Double, previous: Double, color: Color) -> some View {
        card(fillsHeight: true) {
            Label(title, systemImage: title == "收入" ? "arrow.down.left" : title == "支出" ? "arrow.up.right" : "equal.circle")
                .appFont(.body, weight: .semibold).foregroundStyle(color)
            Text(money(current) + " " + currency).appFont(.amount, weight: .semibold).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            Text("期间 B  " + money(previous) + " " + currency).appFont(.caption).foregroundStyle(.secondary)
            Divider()
            Text("差额  " + signed(current - previous) + " " + currency).appFont(.body, weight: .medium)
            Text(abs(previous) < 0.01 ? "期间 B 为 0，变化率不适用" : "变化率  " + ((current - previous) / abs(previous)).formatted(.percent.precision(.fractionLength(1))))
                .appFont(.caption).foregroundStyle(.secondary).appHelp("变化率 = (期间 A − 期间 B) ÷ |期间 B|")
        }.accessibilityElement(children: .combine).accessibilityIdentifier("comparisonMetric-" + title)
    }
    private func card<Content: View>(fillsHeight: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content).padding(18).frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
            .background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 14))
    }
}
