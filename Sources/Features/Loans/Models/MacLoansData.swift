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
        switch value { case .equalPayment: "等额本息"; case .equalPrincipal: "等额本金"; case .interestOnly: "先息后本" }
    }
    static func audit(_ loan: LoanRule, transactions: [Transaction], rules: [RecurringTransaction]) -> Audit {
        func unknown(_ warning: String) -> Audit {
            Audit(reliable: false, receipts: [], paid: [], next: nil, outstanding: nil, warning: warning)
        }
        guard MacLoanSchedule.valid(loan) else { return unknown("贷款计划日期记录损坏，请先核对历史。") }
        guard MacLoanRepayment.isManaged(loan) else {
            return unknown("历史还款待核对，计划日期、关联规则和相似备注不能证明已经付款。")
        }
        let prefix = "loan_generated:\(loan.id.uuidString):"
        guard !rules.contains(where: { ($0.projectIdentifier ?? "").hasPrefix(prefix) }) else {
            return unknown("存在旧贷款关联规则，请先核对历史，避免重复入账。")
        }
        guard loan.principal.isFinite, loan.principal > 0, loan.annualRate.isFinite, (0...100).contains(loan.annualRate),
              (1...600).contains(loan.termMonths), RepaymentMethod(rawValue: loan.methodRawValue) != nil,
              loan.exchangeRateToBase.isFinite, loan.exchangeRateToBase > 0,
              loan.basePrincipal == FinancialPrecision.roundAmountForStorage(loan.principal * loan.exchangeRateToBase),
              loan.currency != loan.baseCurrencyCode || loan.exchangeRateToBase == 1 else { return unknown("贷款参数或记账快照需要核对。") }
        let schedule = MacLoanRepayment.resolvedSchedule(loan, transactions: transactions)
        guard schedule.count == loan.termMonths, schedule.allSatisfy({ $0.total.isFinite && $0.total >= 0 }) else { return unknown("还款计划需要核对。") }
        do {
            let paid = try MacLoanRepayment.verifiedPaidIndices(loan, schedule: schedule, transactions: transactions, book: loan.baseCurrencyCode)
            guard paid == Set(schedule.filter { $0.total > 0 }.prefix(paid.count).map(\.index)) else { return unknown("还款记录不连续，请核对缺失期次。") }
            let payments = schedule.filter { paid.contains($0.index) }
            let markers = Set(payments.map { MacLoanRepayment.marker(loanID: loan.id, payment: $0) })
            let receipts = transactions.filter { row in markers.contains(where: { (row.note ?? "").hasSuffix($0) }) }.sorted { $0.date > $1.date }
            let principal = FinancialPrecision.roundAmountForStorage(payments.reduce(0) { $0 + $1.principal })
            let completed = paid.count == schedule.filter { $0.total > 0 }.count
            let mismatch = completed && abs(principal - loan.principal) >= 0.005
            let review = MacLoanSchedule.requiresReview(loan)
            let warning = review ? "旧贷款未保存合同所在时区。已有收据保持不变；请核对并固定未来还款日期后继续记账。" : (mismatch ? "历史还款存在分币差额；已入账金额保持原值，请核对银行实际结清金额。" : nil)
            return Audit(reliable: true, receipts: receipts, paid: paid, next: review ? nil : schedule.first { $0.total > 0 && !paid.contains($0.index) },
                         outstanding: payments.last?.remainingBalance ?? loan.principal, warning: warning,
                         principalPaid: principal, interestPaid: FinancialPrecision.roundAmountForStorage(payments.reduce(0) { $0 + $1.interest }), schedule: schedule)
        } catch { return unknown("关联收据损坏、重复、已删除或与计划不符；实际进度暂不展示，请到账目中核对。") }
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
