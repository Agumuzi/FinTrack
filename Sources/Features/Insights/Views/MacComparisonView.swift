import SwiftUI
import Charts

struct MacComparisonView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    let transactions: [Transaction]
    let currency: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(L10n.text("mac.comparisonView.body.36af57a907")).appFont(.dialogTitle, weight: .semibold); Spacer(); Button(L10n.text("mac.comparisonView.body.c0b3fbff51")) { dismiss() } }
            ScrollView { MacPeriodComparisonDashboard(transactions: transactions, currency: currency) }
        }.padding(24).appPanel(width: 900, height: 720)
    }
}

struct MacPeriodComparisonDashboard: View {
    @ObservedObject private var localizationState = LocalizationController.shared
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
                    dateRange(L10n.text("mac.comparisonView.dateRange.59bcc187f3"), start: $customStart, end: $customEnd, prefix: "comparisonA")
                    dateRange(L10n.text("mac.comparisonView.dateRange.b51283cf4e"), start: $previousStart, end: $previousEnd, prefix: "comparisonB")
                } else {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.text("mac.comparisonView.card.59bcc187f3")).appFont(.caption).foregroundStyle(.secondary)
                            if mode == "同月跨年" { MacSettingsDateButton(date: $reference, monthOnly: true, identifier: "comparisonMonth") }
                            else { yearMenu($currentYear, id: "comparisonCurrentYear") }
                        }.frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(mode == "同月跨年" ? L10n.text("mac.comparisonView.card.5e6d5db57f") : L10n.text("mac.comparisonView.card.b51283cf4e")).appFont(.caption).foregroundStyle(.secondary)
                            yearMenu($previousYear, id: "comparisonPreviousYear")
                        }.frame(maxWidth: .infinity)
                    }
                }
                if let (a, b) = ranges {
                    Text("A  " + rangeLabel(a) + "    /    B  " + rangeLabel(b)).appFont(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("comparisonRangeSummary")
                    Text(L10n.text("mac.comparisonView.card.df0d33cff0")).appFont(.caption).foregroundStyle(.secondary)
                } else { Text(L10n.text("mac.comparisonView.card.90de26a62a")).foregroundStyle(.red) }
            }
            if let (a, b) = ranges {
                let monthly = mode == "年度对比" || max(a.duration, b.duration) > 90 * 86400
                let snapshot = MacPeriodComparison.snapshot(rows: transactions, currency: currency, current: a, previous: b, flow: flow == "支出" ? .expense : .income, monthly: monthly, calendar: calendar)
                MacAdaptiveEqualCardLayout {
                    metric(L10n.text("mac.comparisonView.metric.117d8f914d"), current: snapshot.current.income, previous: snapshot.previous.income, color: MacOverviewStyle.income, icon: "arrow.down.left")
                    metric(L10n.text("mac.comparisonView.metric.e679096865"), current: snapshot.current.expense, previous: snapshot.previous.expense, color: MacOverviewStyle.expense, icon: "arrow.up.right")
                    metric(L10n.text("mac.comparisonView.metric.d26ca9aea9"), current: snapshot.current.net, previous: snapshot.previous.net, color: MacSettingsVisual.accent, icon: "equal.circle")
                }
                Text(L10n.format("mac.comparisonView.body.1dd65c0af8", Int64(snapshot.currentRows.count), Int64(snapshot.previousRows.count)))
                    .appFont(.caption).foregroundStyle(.secondary).accessibilityIdentifier("insightsTransactionCount")
                if snapshot.currentRows.isEmpty || snapshot.previousRows.isEmpty {
                    Label(snapshot.currentRows.isEmpty && snapshot.previousRows.isEmpty ? L10n.text("mac.comparisonView.body.065d523ef1") : (snapshot.currentRows.isEmpty ? L10n.text("mac.comparisonView.body.7a6e58989c") : L10n.text("mac.comparisonView.body.85e232b3ef")), systemImage: "info.circle")
                        .appFont(.caption).foregroundStyle(.secondary).accessibilityIdentifier("comparisonEmptyNotice")
                }
                card {
                    ViewThatFits {
                        HStack { Text(L10n.text("mac.comparisonView.ViewThatFits.01a96bd794")).appFont(.section, weight: .semibold); Spacer(); flowControl.frame(width: 180) }
                        VStack(alignment: .leading) { Text(L10n.text("mac.comparisonView.ViewThatFits.01a96bd794")).appFont(.section, weight: .semibold); flowControl }
                    }
                    Chart(snapshot.points) { point in
                        if let amount = point.current {
                            BarMark(x: .value(L10n.text("mac.comparisonView.BarMark.1fc12f2e41"), point.index), y: .value(L10n.text("mac.comparisonView.BarMark.ffc624300d"), amount))
                                .foregroundStyle(by: .value(L10n.text("mac.comparisonView.Chart.8adb98534c"), L10n.text("mac.comparisonView.Chart.59bcc187f3"))).position(by: .value(L10n.text("mac.comparisonView.Chart.8adb98534c"), L10n.text("mac.comparisonView.Chart.59bcc187f3")))
                        }
                        if let amount = point.previous {
                            BarMark(x: .value(L10n.text("mac.comparisonView.BarMark.1fc12f2e41"), point.index), y: .value(L10n.text("mac.comparisonView.BarMark.ffc624300d"), amount))
                                .foregroundStyle(by: .value(L10n.text("mac.comparisonView.Chart.8adb98534c"), L10n.text("mac.comparisonView.Chart.b51283cf4e"))).position(by: .value(L10n.text("mac.comparisonView.Chart.8adb98534c"), L10n.text("mac.comparisonView.Chart.b51283cf4e")))
                        }
                    }.chartForegroundStyleScale([L10n.text("mac.comparisonView.Chart.59bcc187f3"): MacSettingsVisual.accent, L10n.text("mac.comparisonView.Chart.b51283cf4e"): Color.blue.opacity(0.6)])
                        .chartXAxis {
                            let stride = max(1, Int(ceil(Double(snapshot.points.count) / Double(monthly ? 12 : 8))))
                            let labels = snapshot.points.filter { ($0.index - 1) % stride == 0 || $0.index == snapshot.points.count }.map(\.index)
                            AxisMarks(values: labels) { value in
                                AxisGridLine(); AxisValueLabel { if let n = value.as(Int.self) { Text(L10n.format(monthly ? "insights.axis.month" : "insights.axis.day", String(n))) } }
                            }
                        }
                        .frame(height: 220).accessibilityIdentifier("periodComparisonChart")
                    Text(L10n.text(monthly ? "insights.axis.month.explanation" : "insights.axis.day.explanation")).appFont(.caption).foregroundStyle(.secondary)
                }
                card {
                    Text(L10n.text(flow == "支出" ? "insights.categories.expense" : "insights.categories.income")).appFont(.section, weight: .semibold)
                    HStack { Text(L10n.text("mac.comparisonView.card.515559957f")); Spacer(); column(L10n.text("mac.comparisonView.column.59bcc187f3")); column(L10n.text("mac.comparisonView.column.b51283cf4e")); column(L10n.text("mac.comparisonView.column.7ba6322890")) }
                        .appFont(.caption).foregroundStyle(.secondary)
                    if snapshot.categories.isEmpty { Text(L10n.text(flow == "支出" ? "insights.categories.expense.empty" : "insights.categories.income.empty")).foregroundStyle(.secondary) }
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
        MacSettingsMenu(selection: year, options: years.map { (L10n.format("insights.year", String($0)), $0) }).accessibilityIdentifier(id)
    }
    private func dateRange(_ title: String, start: Binding<Date>, end: Binding<Date>, prefix: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).appFont(.caption).foregroundStyle(.secondary)
            HStack { MacSettingsDateButton(date: start, identifier: prefix + "Start"); Text(L10n.text("mac.comparisonView.dateRange.65edbf9f1c")).foregroundStyle(.secondary); MacSettingsDateButton(date: end, identifier: prefix + "End") }
        }
    }
    private func rangeLabel(_ interval: DateInterval) -> String {
        MacDateDisplay.string(interval.start) + " – " + MacDateDisplay.string(interval.end.addingTimeInterval(-1))
    }
    private func money(_ value: Double) -> String { MacDisplayPreferences.money(value) }
    private func signed(_ value: Double) -> String { (value > 0 ? "+" : "") + money(value) }
    private func column(_ text: String) -> some View { Text(text).frame(width: 105, alignment: .trailing).fixedSize(horizontal: false, vertical: true) }
    private func metric(_ title: String, current: Double, previous: Double, color: Color, icon: String) -> some View {
        card(fillsHeight: true) {
            Label(title, systemImage: icon)
                .appFont(.body, weight: .semibold).foregroundStyle(color)
            Text(money(current) + " " + currency).appFont(.amount, weight: .semibold).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            Text(L10n.text("mac.comparisonView.card.3006730905") + money(previous) + " " + currency).appFont(.caption).foregroundStyle(.secondary)
            Divider()
            Text(L10n.text("mac.comparisonView.card.0258094391") + signed(current - previous) + " " + currency).appFont(.body, weight: .medium)
            Text(abs(previous) < 0.01 ? L10n.text("mac.comparisonView.card.2fa7dd3f90") : L10n.text("mac.comparisonView.card.b8e2392d8b") + ((current - previous) / abs(previous)).formatted(.percent.precision(.fractionLength(1))))
                .appFont(.caption).foregroundStyle(.secondary).appHelp(L10n.text("mac.comparisonView.card.ab97dce106"))
        }.accessibilityElement(children: .combine).accessibilityIdentifier("comparisonMetric-" + title)
    }
    private func card<Content: View>(fillsHeight: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content).padding(18).frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
            .background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 14))
    }
}
