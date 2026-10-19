import SwiftUI
import SwiftData

struct MacFinanceReviewView: View {
    let record: MacFinanceRecord
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var index = 1
    @State private var confirmed = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(16)) {
            Text("Review stored schedule").appFont(.dialogTitle, weight: .semibold)
            Text("Past cash entries are not inferred from dates, amounts or notes. Choose the first occurrence that has not been recorded in your ledger.")
            switch record {
            case .loan(let loan):
                Stepper("First unrecorded installment: \(index)", value: $index, in: 1...max(loan.termMonths, 1))
                Text("The original repayment schedule will create recurring ledger expenses. This does not initiate bank transfers.")
            case .recurring:
                DatePicker("Next due", selection: $date)
            case .deposit(let deposit):
                if deposit.typedInterestSettlementMode == .monthly { DatePicker("First unrecorded interest date", selection: $date, displayedComponents: .date) }
                Text("Previously settled deposits stay settled. No historic interest receipt is guessed or recreated.")
            case .goal: EmptyView()
            }
            Toggle("I have checked the next unrecorded date against my ledger", isOn: $confirmed)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Use reviewed schedule") {
                    do {
                        switch record {
                        case .loan(let r): try MacFinanceReview.loan(r, firstUnrecordedIndex: index, confirmed: confirmed, in: context)
                        case .recurring(let r): try MacFinanceReview.recurring(r, next: date, confirmed: confirmed, in: context)
                        case .deposit(let r): try MacFinanceReview.deposit(r, firstUnrecorded: date, confirmed: confirmed, in: context)
                        case .goal: break
                        }
                        dismiss()
                    } catch { self.error = MacLocalization.error(error) }
                }.disabled(!confirmed).accessibilityIdentifier("applyReviewedSchedule")
            }
        }.appPadding(24).appDialog(width: 590)
        .onAppear {
            switch record {
            case .deposit(let r): date = r.nextInterestPayoutDate ?? r.maturityDate
            case .recurring(let r): date = r.nextExecutionDate
            default: break
            }
        }
    }
}

struct MacLoanScheduleView: View {
    let loan: LoanRule
    @Environment(\.dismiss) private var dismiss
    private struct Row: Identifiable {
        let payment: LoanAmortizationEngine.Payment
        var id: Int { payment.index }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(12)) {
            Text(loan.title).appFont(.dialogTitle, weight: .semibold)
            Text("Loan schedule").appFont(.section, weight: .semibold)
            Text("\(loan.currency) · \(loan.method.rawValue)")
            Table(loan.amortizationSchedule.map { Row(payment: $0) }) {
                TableColumn("Period") { Text(String($0.payment.index)) }
                TableColumn("Date") { Text(MacDateDisplay.string($0.payment.date)) }
                TableColumn("Principal") { Text($0.payment.principal.formatted(.number.precision(.fractionLength(2)))) }
                TableColumn("Interest") { Text($0.payment.interest.formatted(.number.precision(.fractionLength(2)))) }
                TableColumn("Total") { Text($0.payment.total.formatted(.number.precision(.fractionLength(2)))) }
                TableColumn("Remaining") { Text($0.payment.remainingBalance.formatted(.number.precision(.fractionLength(2)))) }
            }.frame(height: MacUI.space(380)).accessibilityIdentifier("loanScheduleTable")
            HStack { Spacer(); Button("Close") { dismiss() } }
        }.appPadding(24).appDialog(width: 780)
    }
}
