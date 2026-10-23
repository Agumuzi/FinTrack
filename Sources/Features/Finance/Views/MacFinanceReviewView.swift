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
            Text("核对已有计划").appFont(.dialogTitle, weight: .semibold)
            Text("请对照账本，选择首个尚未记账的期次。日期、金额和备注不作为历史收付款的证明。")
            switch record {
            case .loan(let loan):
                Stepper("首个未记账期次：\(index)", value: $index, in: 1...max(loan.termMonths, 1))
                Text("原还款计划会生成周期记账支出，不会发起银行转账。")
            case .recurring:
                MacDateTimeField(title: "下次执行", date: $date, includesTime: true)
            case .deposit(let deposit):
                if deposit.typedInterestSettlementMode == .monthly { MacDateTimeField(title: "首个未记账结息日期", date: $date) }
                Text("已结清存款保持原状态，不推测或补造历史利息收据。")
            case .goal: EmptyView()
            }
            Toggle("我已对照账本核对首个未记账日期", isOn: $confirmed)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("使用已核对计划") {
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
            Text("贷款计划").appFont(.section, weight: .semibold)
            Text("\(loan.currency) · \(loan.method.rawValue)")
            Table(loan.amortizationSchedule.map { Row(payment: $0) }) {
                TableColumn("期次") { Text(String($0.payment.index)) }
                TableColumn("日期") { Text(MacDateDisplay.string($0.payment.date)) }
                TableColumn("本金") { Text($0.payment.principal.formatted(.number.precision(.fractionLength(2)))) }
                TableColumn("利息") { Text($0.payment.interest.formatted(.number.precision(.fractionLength(2)))) }
                TableColumn("合计") { Text($0.payment.total.formatted(.number.precision(.fractionLength(2)))) }
                TableColumn("剩余本金") { Text($0.payment.remainingBalance.formatted(.number.precision(.fractionLength(2)))) }
            }.frame(height: MacUI.space(380)).accessibilityIdentifier("loanScheduleTable")
            HStack { Spacer(); Button("关闭") { dismiss() } }
        }.appPadding(24).appDialog(width: 780)
    }
}
