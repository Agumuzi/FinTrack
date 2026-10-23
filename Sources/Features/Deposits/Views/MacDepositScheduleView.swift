import SwiftUI

struct MacDepositScheduleView: View {
    let deposit: DepositRecord
    @Environment(\.dismiss) private var dismiss
    struct Row: Identifiable { let id: Int; let date: Date; let interest: Double }
    static func rows(for deposit: DepositRecord) -> [Row] {
        MacDepositTerms.schedule(deposit).enumerated().map { Row(id: $0.offset + 1, date: $0.element.date, interest: $0.element.interest) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(14)) {
            Text(deposit.bankName).appFont(.dialogTitle, weight: .semibold)
            Text("Interest schedule").appFont(.section, weight: .semibold)
            Table(Self.rows(for: deposit)) {
                TableColumn("Date") { Text(MacDateDisplay.string($0.date)) }
                TableColumn("Interest") { Text("\($0.interest.formatted(.number.precision(.fractionLength(2)))) \(deposit.originalCurrency)") }
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("depositScheduleDone") }
        }.appPadding(24).appPanel(width: 580, height: 520)
    }
}
