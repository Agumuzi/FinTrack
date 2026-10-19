import SwiftUI

struct MacRecurringScheduleView: View {
    let rule: RecurringTransaction
    @Environment(\.dismiss) private var dismiss
    private struct Row: Identifiable { let id: Int; let date: Date }
    private var rows: [Row] {
        var date = rule.nextExecutionDate
        var rows: [Row] = []
        for index in 1...24 {
            if let end = rule.endDate, date > end { break }
            rows.append(Row(id: index, date: date))
            guard let next = try? MacFinanceRecords.nextDate(date, value: rule.intervalValue, unit: rule.intervalUnit), next > date else { break }
            date = next
        }
        return rows
    }
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(14)) {
            Text(rule.title).appFont(.dialogTitle, weight: .semibold)
            Text("后续计划 · 最多 24 次").appFont(.section, weight: .semibold)
            Text("计划不代表已入账。暂停规则的日期仅供参考；结束日期以最后允许发生的计划为准。").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
            if RecurringIntervalUnit(rawValue: rule.intervalUnit) == nil || !(1...365).contains(rule.intervalValue) {
                Text("频率无效，请先核对规则。").foregroundStyle(.orange)
            } else {
                Table(rows) {
                    TableColumn("计划日期") { Text(MacDateDisplay.string($0.date)) }
                    TableColumn("每次原币金额") { _ in Text("\(MacOverviewStyle.money(rule.originalAmount)) \(rule.originalCurrency)") }
                }.accessibilityIdentifier("recurringScheduleTable")
            }
            HStack { Spacer(); Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("recurringCloseSchedule") }
        }.appPadding(24).appPanel(width: 580, height: 520)
    }
}
