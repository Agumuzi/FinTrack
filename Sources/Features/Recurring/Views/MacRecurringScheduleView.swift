import SwiftUI

struct MacRecurringScheduleView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
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
            Text(L10n.text("mac.recurringScheduleView.body.09737664cc")).appFont(.section, weight: .semibold)
            Text(L10n.text("mac.recurringScheduleView.body.0a4a9bc342")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
            if RecurringIntervalUnit(rawValue: rule.intervalUnit) == nil || !(1...365).contains(rule.intervalValue) {
                Text(L10n.text("mac.recurringScheduleView.body.c9a48c0867")).foregroundStyle(.orange)
            } else {
                Table(rows) {
                    TableColumn(L10n.text("mac.recurringScheduleView.TableColumn.011247215d")) { Text(MacDateDisplay.string($0.date)) }
                    TableColumn(L10n.text("mac.recurringScheduleView.TableColumn.380a85189a")) { _ in Text("\(MacOverviewStyle.money(rule.originalAmount)) \(rule.originalCurrency)") }
                }.accessibilityIdentifier("recurringScheduleTable")
            }
            HStack { Spacer(); Button(L10n.text("mac.recurringScheduleView.body.3fd47edce4")) { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("recurringCloseSchedule") }
        }.appPadding(24).appPanel(width: 580, height: 520)
    }
}
