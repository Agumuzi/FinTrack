import SwiftUI
import SwiftData

struct MacFinanceReviewView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    let record: MacFinanceRecord
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var index = 1
    @State private var confirmed = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(16)) {
            Text(L10n.text("mac.financeReviewView.body.0e4d25c8c9")).appFont(.dialogTitle, weight: .semibold)
            Text(L10n.text("mac.financeReviewView.body.068bbcf4b6"))
            switch record {
            case .loan(let loan):
                Stepper(L10n.format("mac.financeReviewView.Stepper.c9dd72bf4b", "\(index)"), value: $index, in: 1...max(loan.termMonths, 1))
                Text(L10n.text("mac.financeReviewView.body.dbaf7313d4"))
            case .recurring:
                MacDateTimeField(title: L10n.text("mac.financeReviewView.MacDateTimeField.b8e094966d"), date: $date, includesTime: true)
            case .deposit(let deposit):
                if deposit.typedInterestSettlementMode == .monthly { MacDateTimeField(title: L10n.text("mac.financeReviewView.MacDateTimeField.7a24ec7b45"), date: $date) }
                Text(L10n.text("mac.financeReviewView.body.1b5e4aee7b"))
            case .goal: EmptyView()
            }
            Toggle(L10n.text("mac.financeReviewView.body.aaae3b2ba0"), isOn: $confirmed)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(L10n.text("mac.financeReviewView.body.2cd0f3be87")) { dismiss() }
                Button(L10n.text("mac.financeReviewView.body.cb208bc418")) {
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
    @ObservedObject private var localizationState = LocalizationController.shared
    let loan: LoanRule
    @Environment(\.dismiss) private var dismiss
    private struct Row: Identifiable {
        let payment: LoanAmortizationEngine.Payment
        var id: Int { payment.index }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(12)) {
            Text(loan.title).appFont(.dialogTitle, weight: .semibold)
            Text(L10n.text("mac.financeReviewView.body.60fe565c4c")).appFont(.section, weight: .semibold)
            Text("\(loan.currency) · \(loan.method.rawValue)")
            Table(loan.amortizationSchedule.map { Row(payment: $0) }) {
                TableColumn(L10n.text("mac.financeReviewView.TableColumn.4a703a03f5")) { Text(String($0.payment.index)) }
                TableColumn(L10n.text("mac.financeReviewView.TableColumn.70d0c1b336")) { Text(MacDateDisplay.string($0.payment.date)) }
                TableColumn(L10n.text("mac.financeReviewView.TableColumn.2fa66a53e4")) { Text($0.payment.principal.formatted(.number.precision(.fractionLength(2)))) }
                TableColumn(L10n.text("mac.financeReviewView.TableColumn.3dd1b22caa")) { Text($0.payment.interest.formatted(.number.precision(.fractionLength(2)))) }
                TableColumn(L10n.text("mac.financeReviewView.TableColumn.e009c148d1")) { Text($0.payment.total.formatted(.number.precision(.fractionLength(2)))) }
                TableColumn(L10n.text("mac.financeReviewView.TableColumn.42a94e5205")) { Text($0.payment.remainingBalance.formatted(.number.precision(.fractionLength(2)))) }
            }.frame(height: MacUI.space(380)).accessibilityIdentifier("loanScheduleTable")
            HStack { Spacer(); Button(L10n.text("mac.financeReviewView.body.3fd47edce4")) { dismiss() } }
        }.appPadding(24).appDialog(width: 780)
    }
}
