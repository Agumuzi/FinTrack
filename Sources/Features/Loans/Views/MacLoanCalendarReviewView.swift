import SwiftUI
import SwiftData

/// Only legacy contracts lacking pinned dates reach this explicit review.
struct MacLoanCalendarReviewView: View {
    let loan: LoanRule
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var transactions: [Transaction]
    @State private var zone = TimeZone.current.identifier
    @State private var confirmed = false
    @State private var error: String?
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: zone) ?? .current
        return value
    }
    private var schedule: [LoanAmortizationEngine.Payment] {
        MacLoanRepayment.resolvedSchedule(loan, transactions: transactions, calendar: calendar)
    }
    private func date(_ value: Date) -> String {
        let format = DateFormatter(); format.calendar = calendar; format.timeZone = calendar.timeZone
        format.dateFormat = "yyyy-MM-dd HH:mm zzz"
        return format.string(from: value)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("核对旧贷款还款日期").appFont(.dialogTitle, weight: .semibold)
            Text("旧记录没有保存合同所在时区，无法自动还原。请选择合同所在时区并逐期核对未来日期；已有还款收据、金额和日期保持不变。")
            Picker("合同所在时区", selection: $zone) {
                ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
            }.accessibilityIdentifier("loanContractTimezone")
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(schedule, id: \.index) { payment in
                        Text("第 \(payment.index) 期 · \(date(payment.date)) · \(MacOverviewStyle.money(payment.total)) \(loan.currency)")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 280).accessibilityIdentifier("loanCalendarDates")
            Toggle("我已对照合同核对以上日期", isOn: $confirmed).accessibilityIdentifier("loanCalendarConfirmed")
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("取消") { dismiss() }; Spacer()
                Button("固定已核对日期") {
                    do {
                        try MacLoanSchedule.confirmLegacy(loan, calendar: calendar, expectedDates: schedule.map(\.date), in: context)
                        dismiss()
                    } catch { self.error = MacLocalization.error(error) }
                }.disabled(!confirmed).accessibilityIdentifier("loanCalendarApply")
            }
        }.appPadding(24).appDialog(width: 700)
        .onChange(of: zone) { _, _ in confirmed = false }
    }
}
