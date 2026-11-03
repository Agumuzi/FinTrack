import Foundation

/// Derived only. A settlement's marker, not its transaction date, assigns its
/// planned year. No model, cursor, FX snapshot or posting operation is mutated.
@MainActor enum MacDepositEarnings {
    static func percentage(_ amount: Decimal, total: Decimal) -> String {
        guard total > 0 else { return "0%" }
        let fraction = min(1, max(0, NSDecimalNumber(decimal: amount / total).doubleValue))
        return fraction.formatted(.percent.precision(.fractionLength(0)))
    }
    struct Revision: Hashable {
        let deposits: [[String]]
        let receipts: [[String]]
        let year: Int
        let zone: String
        init(deposits: [DepositRecord], transactions: [Transaction], now: Date, calendar: Calendar = .current) {
            self.year = calendar.component(.year, from: now); zone = calendar.timeZone.identifier
            self.deposits = deposits.map { row in
                [row.id.uuidString, String(describing: row.deletedAt), String(row.isActive), String(row.hasCreditedInterest),
                 String(describing: row.lastInterestPayoutDate), String(row.startDate.timeIntervalSince1970), String(row.maturityDate.timeIntervalSince1970),
                 String(row.principal), String(row.annualInterestRate), row.interestSettlementMode, String(row.expectedInterest),
                 String(row.isInterestManuallyEdited), row.originalCurrency, row.baseCurrencyCode]
            }
            self.receipts = transactions.filter { ($0.note ?? "").contains("[FTDep:") }.map { row in
                [row.id.uuidString, String(describing: row.deletedAt), row.type, row.originalCurrency, row.baseCurrencyCode,
                 String(row.originalAmount), String(row.baseAmount), String(row.exchangeRateToBase), String(row.date.timeIntervalSince1970), row.note ?? ""]
            }
        }
    }
    struct CurrencyTotal: Equatable, Identifiable {
        let currency: String
        var received: Decimal = 0
        var outstanding: Decimal = 0
        var total: Decimal { received + outstanding }
        var id: String { currency }
    }
    struct YearTotal: Equatable, Identifiable {
        let year: Int
        let currencies: [CurrencyTotal]
        var id: Int { year }
    }
    struct Snapshot: Equatable {
        let year: Int
        let outstanding: [CurrencyTotal]
        let current: [CurrencyTotal]
        let future: [YearTotal]
        let outstandingYears: [YearTotal]
        let excludedDeposits: Int
        static let empty = Snapshot(year: 0, outstanding: [], current: [], future: [], outstandingYears: [], excludedDeposits: 0)
    }
    static func amount(_ value: Double) -> Decimal? {
        guard value.isFinite, value >= 0,
              var source = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        var result = Decimal()
        NSDecimalRound(&result, &source, FinancialPrecision.amountStorageScale, .plain)
        return result
    }
    static func snapshot(deposits: [DepositRecord], transactions: [Transaction],
                         now: Date = Date(), calendar: Calendar = .current) -> Snapshot {
        let year = calendar.component(.year, from: now)
        // Index the already-loaded query once. Unrelated transactions cannot
        // become interest merely because their date, bank or amount looks similar.
        var indexed: [UUID: [Transaction]] = [:]
        for receipt in transactions where receipt.deletedAt == nil {
            if let identity = MacDepositsData.receiptIdentity(receipt.note) {
                indexed[identity.depositID, default: []].append(receipt)
            } else if let note = receipt.note, note.contains("[FTDep:") {
                // Preserve damaged markers as anomalies for the matching deposit.
                let ids = note.components(separatedBy: "[FTDep:").dropFirst().compactMap { UUID(uuidString: String($0.prefix(36))) }
                for id in Set(ids) { indexed[id, default: []].append(receipt) }
            }
        }
        var byYear: [Int: [String: CurrencyTotal]] = [:], remaining: [String: CurrencyTotal] = [:]
        var excluded = 0
        for deposit in deposits where deposit.deletedAt == nil {
            let periods = MacDepositTerms.schedule(deposit)
            let receipts = indexed[deposit.id] ?? []
            let audit = MacDepositsData.audit(deposit, transactions: receipts, periods: periods, allowsActualReceiptDate: true)
            let currency = deposit.originalCurrency
            guard !periods.isEmpty, Set(periods.map(\.date)).count == periods.count,
                  periods.last?.date == deposit.maturityDate,
                  periods.allSatisfy({ amount($0.interest) != nil }),
                  (try? MacCurrency.code(currency)) == currency, audit.unverifiedCount == 0,
                  audit.receipts.allSatisfy({ amount($0.originalAmount) != nil }) else { excluded += 1; continue }
            let monthly = deposit.typedInterestSettlementMode == .monthly
            let byMarker = Dictionary(uniqueKeysWithValues: audit.receipts.compactMap { row in
                MacDepositsData.receiptIdentity(row.note).map { ($0.marker, row) }
            })
            // Old credited flags and payout cursors alone are not payment proof.
            let missingHistory = periods.contains { period in
                let needsReceipt = deposit.hasCreditedInterest || deposit.lastInterestPayoutDate.map { period.date <= $0 } == true
                return period.interest > 0 && needsReceipt && byMarker[MacDepositSettlement.receiptMarker(depositID: deposit.id, date: period.date, monthly: monthly)] == nil
            }
            if missingHistory { excluded += 1; continue }
            let stoppedWithoutSettlement = !deposit.isActive && !deposit.hasCreditedInterest
            if stoppedWithoutSettlement { excluded += 1 }
            for period in periods {
                let expected = amount(period.interest)!
                let marker = MacDepositSettlement.receiptMarker(depositID: deposit.id, date: period.date, monthly: monthly)
                let receipt = byMarker[marker]
                let note = receipt?.note ?? ""
                // Explicit manual posting is a confirmation in the existing app.
                // Automatic posting always carries FTEstimated, even after maturity.
                let confirmed = receipt != nil && !note.contains("[FTEstimated]")
                let received = confirmed ? amount(receipt!.originalAmount)! : 0
                let pending: Decimal
                if stoppedWithoutSettlement { pending = 0 }
                else if !confirmed { pending = expected }
                else if note.contains("[FTPartial]") { pending = max(0, expected - received) }
                else { pending = 0 } // A final bank adjustment closes the period.
                guard received > 0 || pending > 0 else { continue }
                let plannedYear = calendar.component(.year, from: period.date)
                var value = byYear[plannedYear, default: [:]][currency] ?? CurrencyTotal(currency: currency)
                value.received += received; value.outstanding += pending
                byYear[plannedYear, default: [:]][currency] = value
                if pending > 0 {
                    var total = remaining[currency] ?? CurrencyTotal(currency: currency)
                    total.outstanding += pending; remaining[currency] = total
                }
            }
        }
        func ordered(_ values: [String: CurrencyTotal]) -> [CurrencyTotal] { values.values.sorted { $0.currency < $1.currency } }
        let outstandingYears = byYear.keys.sorted().compactMap { key -> YearTotal? in
            let rows = ordered(byYear[key] ?? [:]).filter { $0.outstanding > 0 }
            return rows.isEmpty ? nil : YearTotal(year: key, currencies: rows)
        }
        return Snapshot(year: year, outstanding: ordered(remaining), current: ordered(byYear[year] ?? [:]), future: outstandingYears.filter { $0.year > year }, outstandingYears: outstandingYears, excludedDeposits: excluded)
    }
}
