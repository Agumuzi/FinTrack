import Foundation
import SwiftData

/// Pins the exact contract dates without changing the SwiftData schema. The
/// opaque metadata travels with native/CSV backups; UI notes hide it.
@MainActor
enum MacLoanSchedule {
    static let prefix = "[FTLoan:Schedule:"
    private struct Dates: Codable { let version: Int; let start: Date; let count: Int; let dates: [Date] }
    static func metadata(_ note: String) -> String? {
        guard let start = note.range(of: prefix), let end = note[start.upperBound...].firstIndex(of: "]") else { return nil }
        return String(note[start.lowerBound...end])
    }
    static func dates(_ loan: LoanRule) -> [Date]? {
        guard let text = metadata(loan.note), let bytes = Data(base64Encoded: String(text.dropFirst(prefix.count).dropLast())),
              let saved = try? JSONDecoder().decode(Dates.self, from: bytes), saved.version == 1,
              saved.count == loan.termMonths, saved.dates.count == loan.termMonths,
              saved.dates.allSatisfy({$0.timeIntervalSince1970.isFinite && abs($0.timeIntervalSince1970)<253402300800}),
              saved.start.timeIntervalSince1970.isFinite,abs(saved.start.timeIntervalSince1970)<253402300800,
              loan.startDate.timeIntervalSince1970.isFinite,abs(loan.startDate.timeIntervalSince1970)<253402300800,
              Int64(saved.start.timeIntervalSince1970) == Int64(loan.startDate.timeIntervalSince1970),
              saved.dates.first.map({Int64($0.timeIntervalSince1970)}) == Int64(loan.startDate.timeIntervalSince1970),
              zip(saved.dates, saved.dates.dropFirst()).allSatisfy({ $0 < $1 }) else { return nil }
        return saved.dates
    }
    static func valid(_ loan: LoanRule) -> Bool {loan.startDate.timeIntervalSince1970.isFinite && abs(loan.startDate.timeIntervalSince1970)<253402300800 && (!loan.note.contains(prefix) || dates(loan) != nil)}
    static func requiresReview(_ loan: LoanRule) -> Bool {
        MacLoanRepayment.isManaged(loan) && !loan.note.contains(prefix)
    }
    static func pin(_ loan: LoanRule, replacingExisting: Bool = false) throws {
        if loan.note.contains(prefix), !replacingExisting {
            guard dates(loan) != nil else { throw MacSettingsFailure.invalid("贷款计划日期记录损坏，请先核对历史。") }
            return
        }
        let schedule = LoanAmortizationEngine.legacySchedule(principal: loan.principal, annualRate: loan.annualRate,
            termMonths: loan.termMonths, method: loan.method, firstPaymentDate: loan.startDate)
        try pin(loan, dates: schedule.map(\.date))
    }
    private static func pin(_ loan: LoanRule, dates: [Date]) throws {
        guard dates.count == loan.termMonths, dates.first == loan.startDate,
              zip(dates, dates.dropFirst()).allSatisfy({ $0 < $1 }) else {
            throw MacSettingsFailure.invalid("贷款计划日期无效，请核对首期日期和期数。")
        }
        let bytes = try JSONEncoder().encode(Dates(version: 1, start: loan.startDate, count: loan.termMonths, dates: dates))
        let clean = loan.note.replacingOccurrences(of: #"\[FTLoan(?::Schedule|Schedule):[^\]]*\]"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        loan.note = clean + "\n" + prefix + bytes.base64EncodedString() + "]"
    }
    static func confirmLegacy(_ loan: LoanRule, calendar: Calendar, expectedDates: [Date], in context: ModelContext) throws {
        try MacRecoveryJournal.assertWritable(in: context)
        guard !MacAutomaticPosting.isRunning, !context.hasChanges, requiresReview(loan) else {
            throw MacSettingsFailure.invalid("贷款状态已变化，请重新打开核对计划。")
        }
        let rows = try context.fetch(FetchDescriptor<Transaction>())
        let schedule = MacLoanRepayment.resolvedSchedule(loan, transactions: rows, calendar: calendar)
        _ = try MacLoanRepayment.verifiedPaidIndices(loan, schedule: schedule, transactions: rows, book: loan.baseCurrencyCode)
        guard expectedDates == schedule.map(\.date) else { throw MacSettingsFailure.invalid("贷款计划已变化，请重新核对。") }
        try MacRecoveryJournal.perform(in: context) {
            try pin(loan, dates: expectedDates)
            try context.save()
            MacRecoveryJournal.checkpoint("database")
        }
    }
}
