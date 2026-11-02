import SwiftUI
import SwiftData

/// Only legacy contracts lacking pinned dates reach this explicit review.
struct MacLoanCalendarReviewView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
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
            Text(L10n.text("mac.loanCalendarReviewView.body.21f7d3eee9")).appFont(.dialogTitle, weight: .semibold)
            Text(L10n.text("mac.loanCalendarReviewView.body.778f158c9f"))
            Picker(L10n.text("mac.loanCalendarReviewView.Picker.1e674e730d"), selection: $zone) {
                ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
            }.accessibilityIdentifier("loanContractTimezone")
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(schedule, id: \.index) { payment in
                        Text(L10n.format("mac.loanCalendarReviewView.ForEach.a10ec45985", "\(payment.index)", "\(date(payment.date))", "\(MacOverviewStyle.money(payment.total))", "\(loan.currency)"))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 280).accessibilityIdentifier("loanCalendarDates")
            Toggle(L10n.text("mac.loanCalendarReviewView.body.db9808d8b7"), isOn: $confirmed).accessibilityIdentifier("loanCalendarConfirmed")
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button(L10n.text("mac.loanCalendarReviewView.body.2cd0f3be87")) { dismiss() }; Spacer()
                Button(L10n.text("mac.loanCalendarReviewView.body.9754e59f4b")) {
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
