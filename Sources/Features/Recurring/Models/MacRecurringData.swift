import Foundation
import SwiftData

@MainActor
enum MacRecurringData {
    enum Status: String, CaseIterable, Identifiable {
        case active = "启用中", paused = "已暂停", ended = "已结束"
        var id: String { rawValue }
    }
    enum Sort: String, CaseIterable, Identifiable {
        case next = "下次计划最近优先", title = "项目名称", amount = "原币金额从高到低"
        var id: String { rawValue }
    }
    static func status(_ rule: RecurringTransaction) -> Status {
        // A past deadline alone does not erase outstanding, unposted occurrences.
        if let end = rule.endDate, rule.nextExecutionDate > end { return .ended }
        return rule.isActive ? .active : .paused
    }
    static func isLoan(_ rule: RecurringTransaction) -> Bool {
        (rule.projectIdentifier ?? "").hasPrefix("loan_generated:")
    }
    static func frequency(_ rule: RecurringTransaction) -> String {
        guard let unit = RecurringIntervalUnit(rawValue: rule.intervalUnit), (1...365).contains(rule.intervalValue) else { return "频率待核对" }
        let label: String
        switch unit { case .day: label = "天"; case .week: label = "周"; case .month: label = "个月"; case .year: label = "年" }
        return "每 \(rule.intervalValue) \(label)"
    }
    static func filtered(_ rules: [RecurringTransaction], search: String, type: RecurringTransactionType?, status selected: Status?, category: String?, currency: String?, sort: Sort) -> [RecurringTransaction] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return rules.filter {
            $0.deletedAt == nil && (type == nil || $0.typedType == type) && (selected == nil || status($0) == selected) &&
            (category == nil || $0.category == category) && (currency == nil || $0.originalCurrency == currency) &&
            (needle.isEmpty || [$0.title, $0.category, $0.originalCurrency, MacFinanceNotes.visible($0.note)].contains { $0.localizedCaseInsensitiveContains(needle) })
        }.sorted {
            switch sort {
            case .next: if $0.nextExecutionDate != $1.nextExecutionDate { return $0.nextExecutionDate < $1.nextExecutionDate }
            case .title: if $0.title != $1.title { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            case .amount:
                // Keep currencies grouped; different denominations are not comparable.
                if $0.originalCurrency != $1.originalCurrency { return $0.originalCurrency < $1.originalCurrency }
                if $0.originalAmount != $1.originalAmount { return $0.originalAmount > $1.originalAmount }
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    struct Audit {
        let receipts: [Transaction]
        let unverifiedCount: Int
    }
    static func audit(_ rule: RecurringTransaction, transactions: [Transaction]) -> Audit {
        let prefix = "[FTRec:\(rule.id.uuidString):"
        let candidates = transactions.filter { $0.deletedAt == nil && ($0.note ?? "").contains(prefix) }
        let verified = candidates.filter { entry in
            let marker = MacFinanceRecords.occurrenceMarker(ruleID: rule.id, date: entry.date)
            // Historical amounts/type/currency can differ after editing a rule.
            // Verify each receipt against its own immutable accounting snapshot.
            return (entry.note ?? "").components(separatedBy: prefix).count == 2 &&
                (entry.note ?? "").contains(marker) &&
                candidates.filter { ($0.note ?? "").contains(marker) }.count == 1 &&
                ["Income", "Expense", "income", "expense"].contains(entry.type) &&
                entry.originalAmount.isFinite && entry.originalAmount > 0 &&
                entry.exchangeRateToBase.isFinite && entry.exchangeRateToBase > 0 &&
                entry.originalCurrency.count == 3 && entry.baseCurrencyCode.count == 3 &&
                entry.currency == entry.baseCurrencyCode && entry.amount == entry.baseAmount &&
                entry.baseAmount == FinancialPrecision.roundAmountForStorage(entry.originalAmount * entry.exchangeRateToBase) &&
                (entry.originalCurrency != entry.baseCurrencyCode || entry.exchangeRateToBase == 1)
        }
        return Audit(receipts: verified.sorted { $0.date > $1.date }, unverifiedCount: candidates.count - verified.count)
    }
    static func setActive(_ rule: RecurringTransaction, active: Bool, in context: ModelContext) throws {
        try MacRecoveryJournal.assertWritable(in:context)
        guard rule.deletedAt == nil, !isLoan(rule), status(rule) != .ended else { throw MacFinanceReview.Failure.schedule }
        if active {
            guard MacFinanceRecords.isManagedRecurring(rule), (1...365).contains(rule.intervalValue),
                  RecurringIntervalUnit(rawValue: rule.intervalUnit) != nil else { throw MacFinanceReview.Failure.schedule }
        }
        rule.isActive = active; rule.updatedAt = Date()
        if rule.syncVersion < Int.max { rule.syncVersion += 1 }
        do { try context.save() } catch { context.rollback(); throw error }
    }
}
