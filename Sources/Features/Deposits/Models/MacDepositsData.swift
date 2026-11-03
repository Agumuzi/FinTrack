import Foundation

/// Read-only presentation rules. Maturity is a date, never proof of payment.
enum MacDepositsData {
    enum Status: String, CaseIterable, Identifiable {
        case active = "进行中", soon = "即将到期", matured = "已到期", ended = "已结束"
        var id: String { rawValue }
    }
    enum Sort: String, CaseIterable, Identifiable {
        case maturity = "到期日最近优先", bank = "银行名称", rate = "年利率从高到低"
        var id: String { rawValue }
    }
    static func status(_ deposit: DepositRecord, now: Date = Date(), calendar: Calendar = .current) -> Status {
        let today = calendar.startOfDay(for: now), end = calendar.startOfDay(for: deposit.maturityDate)
        if !deposit.isActive { return .ended }
        if end <= today { return .matured }
        let days = calendar.dateComponents([.day], from: today, to: end).day ?? Int.max
        return days <= 30 ? .soon : .active
    }
    static func matches(_ actual: Status, filter: Status?) -> Bool {
        guard let filter else { return true }
        return filter == .matured ? actual == .matured || actual == .ended : actual == filter
    }
    static func filtered(_ deposits: [DepositRecord], search: String, status selected: Status?, bank: String?, currency: String?, year: Int? = nil, sort: Sort, now: Date = Date()) -> [DepositRecord] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return deposits.filter {
            $0.deletedAt == nil && matches(status($0, now: now), filter: selected) &&
            (year == nil || Calendar.current.component(.year, from: $0.maturityDate) == year) &&
            (bank == nil || $0.bankName == bank) && (currency == nil || $0.originalCurrency == currency) &&
            (needle.isEmpty || [$0.bankName, $0.originalCurrency, MacFinanceNotes.visible($0.note)].contains { $0.localizedCaseInsensitiveContains(needle) })
        }.sorted {
            switch sort {
            case .maturity:
                let today = Calendar.current.startOfDay(for: now)
                let lhsUpcoming = Calendar.current.startOfDay(for: $0.maturityDate) > today
                let rhsUpcoming = Calendar.current.startOfDay(for: $1.maturityDate) > today
                if lhsUpcoming != rhsUpcoming { return lhsUpcoming }
                if $0.maturityDate != $1.maturityDate { return lhsUpcoming ? $0.maturityDate < $1.maturityDate : $0.maturityDate > $1.maturityDate }
            case .bank:
                if $0.bankName != $1.bankName { return $0.bankName.localizedStandardCompare($1.bankName) == .orderedAscending }
            case .rate:
                if $0.annualInterestRate != $1.annualInterestRate { return $0.annualInterestRate > $1.annualInterestRate }
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    struct Timing {
        let total: Int, elapsed: Int, remaining: Int
        var progress: Double { total > 0 ? Double(elapsed) / Double(total) : 0 }
    }
    static func timing(_ deposit: DepositRecord, now: Date = Date(), calendar: Calendar = .current) -> Timing {
        let start = calendar.startOfDay(for: deposit.startDate), end = calendar.startOfDay(for: deposit.maturityDate)
        let today = calendar.startOfDay(for: now)
        let total = max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
        let elapsed = min(total, max(0, calendar.dateComponents([.day], from: start, to: today).day ?? 0))
        let remaining = max(0, calendar.dateComponents([.day], from: today, to: end).day ?? 0)
        return Timing(total: total, elapsed: elapsed, remaining: remaining)
    }
    static func mode(_ deposit: DepositRecord) -> String {
        switch deposit.typedInterestSettlementMode {
        case .monthly: L10n.text("mac.depositsData.mode.02fe877b1a")
        case .monthlyCompound: L10n.text("mac.depositsData.mode.d3b39619d1")
        case .maturity: L10n.text("mac.depositsData.mode.ea527e41dd")
        }
    }
    struct ReceiptAudit {
        let receipts: [Transaction]
        let unverifiedCount: Int
        var pendingCount: Int { receipts.filter { ($0.note ?? "").contains("[FTEstimated]") }.count }
        var partialCount: Int { receipts.filter { ($0.note ?? "").contains("[FTPartial]") && !($0.note ?? "").contains("[FTEstimated]") }.count }
        var postedTotal: Double { FinancialPrecision.roundAmountForStorage(receipts.reduce(0) { $0 + $1.originalAmount }) }
        var total: Double { FinancialPrecision.roundAmountForStorage(receipts.filter { !($0.note ?? "").contains("[FTEstimated]") }.reduce(0) { $0 + $1.originalAmount }) }
    }
    /// Require stable identity, schedule/date/amount and the stored FX snapshot.
    /// Ambiguous or damaged receipts stay visible as an anomaly, outside totals.
    static func receiptIdentity(_ note: String?) -> (depositID: UUID, marker: String)? {
        let parts = (note ?? "").components(separatedBy: "[FTDep:")
        guard parts.count == 2, let end = parts[1].firstIndex(of: "]") else { return nil }
        let body = String(parts[1][..<end]), fields = body.split(separator: ":")
        guard fields.count == 3, let id = UUID(uuidString: String(fields[0])), Int64(fields[1]) != nil,
              fields[2] == "MP" || fields[2] == "MAT" else { return nil }
        return (id, "[FTDep:" + body + "]")
    }
    static func audit(_ deposit: DepositRecord, transactions: [Transaction],
                      periods: [MacDepositTerms.Period]? = nil, allowsActualReceiptDate: Bool = false) -> ReceiptAudit {
        let prefix = "[FTDep:\(deposit.id.uuidString):"
        let candidates = transactions.filter { $0.deletedAt == nil && ($0.note ?? "").contains(prefix) }
        let schedule = periods ?? MacDepositTerms.schedule(deposit)
        let monthly = deposit.typedInterestSettlementMode == .monthly
        let periodsByMarker = Dictionary(schedule.map {
            (MacDepositSettlement.receiptMarker(depositID: deposit.id, date: $0.date, monthly: monthly), $0)
        }, uniquingKeysWith: { first, _ in first })
        let grouped = Dictionary(grouping: candidates, by: { receiptIdentity($0.note)?.marker ?? "" })
        var verified: [Transaction] = []
        for entry in candidates {
            guard entry.typedType == .income, entry.originalCurrency == deposit.originalCurrency,
                  entry.baseCurrencyCode == deposit.baseCurrencyCode,
                  entry.currency == entry.baseCurrencyCode,
                  entry.originalAmount.isFinite, entry.originalAmount >= 0,
                  entry.exchangeRateToBase.isFinite, entry.exchangeRateToBase > 0,
                  entry.baseAmount == FinancialPrecision.roundAmountForStorage(entry.originalAmount * entry.exchangeRateToBase),
                  entry.amount == entry.baseAmount,
                  let identity = receiptIdentity(entry.note),
                  let period = periodsByMarker[identity.marker],
                  (allowsActualReceiptDate || entry.date == period.date),
                  (abs(entry.originalAmount - period.interest) < 0.005 || (entry.note ?? "").contains("[FTVerified]")),
                  grouped[identity.marker]?.count == 1
            else { continue }
            verified.append(entry)
        }
        return ReceiptAudit(receipts: verified.sorted { $0.date > $1.date }, unverifiedCount: candidates.count - verified.count)
    }
}
