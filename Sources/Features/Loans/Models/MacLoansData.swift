import Foundation

/// Read-only presentation built from the posting adapter's strict receipt checks.
/// Schedule dates never establish a payment or reduce the displayed actual debt.
enum MacLoansData {
    enum Status: String, CaseIterable, Identifiable {
        case active = "进行中", soon = "七日内应还", overdue = "计划已逾期", settled = "已结清", review = "待核对"
        var id: String { rawValue }
    }
    enum Sort: String, CaseIterable, Identifiable {
        case next = "下一期日期", name = "贷款名称", principal = "贷款本金"
        var id: String { rawValue }
    }
    struct Audit {
        let reliable: Bool
        let receipts: [Transaction]
        let paid: Set<Int>
        let next: LoanAmortizationEngine.Payment?
        let outstanding: Double?
        let warning: String?
        var principalPaid: Double? // From verified original amortization components.
        var interestPaid: Double?
        var schedule: [LoanAmortizationEngine.Payment] = []
    }
    static func method(_ value: RepaymentMethod) -> String {
        switch value { case .equalPayment: L10n.text("mac.loansData.method.3377559ece"); case .equalPrincipal: L10n.text("mac.loansData.method.8344df2ee1"); case .interestOnly: L10n.text("mac.loansData.method.a9d9c962cb") }
    }
    static func audit(_ loan: LoanRule, transactions: [Transaction], rules: [RecurringTransaction]) -> Audit {
        func unknown(_ warning: String) -> Audit {
            Audit(reliable: false, receipts: [], paid: [], next: nil, outstanding: nil, warning: warning)
        }
        guard MacLoanSchedule.valid(loan) else { return unknown(L10n.text("mac.loansData.unknown.51489be39b")) }
        guard MacLoanRepayment.isManaged(loan) else {
            return unknown(L10n.text("mac.loansData.unknown.76a27987d4"))
        }
        let prefix = "loan_generated:\(loan.id.uuidString):"
        guard !rules.contains(where: { ($0.projectIdentifier ?? "").hasPrefix(prefix) }) else {
            return unknown(L10n.text("mac.loansData.unknown.a9de1fb8a8"))
        }
        guard loan.principal.isFinite, loan.principal > 0, loan.annualRate.isFinite, (0...100).contains(loan.annualRate),
              (1...600).contains(loan.termMonths), RepaymentMethod(rawValue: loan.methodRawValue) != nil,
              loan.exchangeRateToBase.isFinite, loan.exchangeRateToBase > 0,
              loan.basePrincipal == FinancialPrecision.roundAmountForStorage(loan.principal * loan.exchangeRateToBase),
              loan.currency != loan.baseCurrencyCode || loan.exchangeRateToBase == 1 else { return unknown(L10n.text("mac.loansData.unknown.b2f0956771")) }
        let schedule = MacLoanRepayment.resolvedSchedule(loan, transactions: transactions)
        guard schedule.count == loan.termMonths, schedule.allSatisfy({ $0.total.isFinite && $0.total >= 0 }) else { return unknown(L10n.text("mac.loansData.unknown.cc2ba8a3f6")) }
        do {
            let paid = try MacLoanRepayment.verifiedPaidIndices(loan, schedule: schedule, transactions: transactions, book: loan.baseCurrencyCode)
            guard paid == Set(schedule.filter { $0.total > 0 }.prefix(paid.count).map(\.index)) else { return unknown(L10n.text("mac.loansData.unknown.9fd70de509")) }
            let payments = schedule.filter { paid.contains($0.index) }
            let markers = Set(payments.map { MacLoanRepayment.marker(loanID: loan.id, payment: $0) })
            let receipts = transactions.filter { row in markers.contains(where: { (row.note ?? "").hasSuffix($0) }) }.sorted { $0.date > $1.date }
            let principal = FinancialPrecision.roundAmountForStorage(payments.reduce(0) { $0 + $1.principal })
            let completed = paid.count == schedule.filter { $0.total > 0 }.count
            let mismatch = completed && abs(principal - loan.principal) >= 0.005
            let review = MacLoanSchedule.requiresReview(loan)
            let warning = review ? L10n.text("mac.loansData.warning.8fa5c64539") : (mismatch ? L10n.text("mac.loansData.warning.c4110d48ca") : nil)
            return Audit(reliable: true, receipts: receipts, paid: paid, next: review ? nil : schedule.first { $0.total > 0 && !paid.contains($0.index) },
                         outstanding: payments.last?.remainingBalance ?? loan.principal, warning: warning,
                         principalPaid: principal, interestPaid: FinancialPrecision.roundAmountForStorage(payments.reduce(0) { $0 + $1.interest }), schedule: schedule)
        } catch { return unknown(L10n.text("mac.loansData.unknown.e58ec8b88c")) }
    }
    static func status(_ audit: Audit, now: Date = Date(), calendar: Calendar = .current) -> Status {
        guard audit.reliable else { return .review }
        guard let next = audit.next else { return audit.warning == nil ? .settled : .review }
        let today = calendar.startOfDay(for: now), due = calendar.startOfDay(for: next.date)
        if due < today { return .overdue }
        if due <= calendar.date(byAdding: .day, value: 7, to: today)! { return .soon }
        return .active
    }
    static func matches(_ actual: Status, filter: Status?) -> Bool {
        guard let filter else { return true }
        return filter == .active ? [.active, .soon, .overdue].contains(actual) : filter == actual
    }
    static func filtered(_ loans: [LoanRule], audits: [UUID: Audit], search: String, status: Status?, category: String?, currency: String?, sort: Sort, now: Date = Date()) -> [LoanRule] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return loans.filter { loan in
            loan.deletedAt == nil && (category == nil || category == loan.category) && (currency == nil || currency == loan.currency) &&
            matches(audits[loan.id].map { self.status($0, now: now) } ?? .review, filter: status) &&
            (query.isEmpty || "\(loan.title) \(loan.category) \(MacOverviewStyle.category(loan.category)) \(MacFinanceNotes.visible(loan.note))".localizedStandardContains(query))
        }.sorted { a, b in
            switch sort {
            case .name: if a.title != b.title { return a.title.localizedStandardCompare(b.title) == .orderedAscending }
            case .principal:
                if a.currency != b.currency { return a.currency < b.currency }
                if a.principal != b.principal { return a.principal > b.principal }
            case .next:
                let x = audits[a.id]?.next?.date ?? .distantFuture, y = audits[b.id]?.next?.date ?? .distantFuture
                if x != y { return x < y }
            }
            return a.id.uuidString < b.id.uuidString
        }
    }
}
