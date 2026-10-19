import SwiftUI

struct MacDepositScheduleView: View {
    let deposit: DepositRecord
    @Environment(\.dismiss) private var dismiss
    struct Row: Identifiable { let id: Int; let date: Date; let interest: Double }
    static func rows(for deposit: DepositRecord) -> [Row] {
        if deposit.typedInterestSettlementMode != .monthly {
            return [Row(id: 1, date: deposit.maturityDate, interest: DepositSettlementRule.maturitySettlementInterest(
                principal: deposit.principal, annualInterestRate: deposit.annualInterestRate, startDate: deposit.startDate,
                maturityDate: deposit.maturityDate, settlementMode: deposit.typedInterestSettlementMode))]
        }
        var rows: [Row] = [], start = deposit.startDate
        for index in 1...1200 {
            guard start < deposit.maturityDate, let next = Calendar.current.date(byAdding: .month, value: 1, to: start), next > start else { break }
            let due = min(next, deposit.maturityDate)
            rows.append(Row(id: index, date: due, interest: DepositSettlementRule.periodicPayoutInterest(
                principal: deposit.principal, annualInterestRate: deposit.annualInterestRate, from: start, to: due)))
            start = due
        }
        return rows
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
