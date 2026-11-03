import Foundation
import SwiftData

/// Stored on the existing profile: additive optional schema field, no new model
/// identity. Internal movements never become income/expense CSV transactions.
nonisolated struct LiquidityState: Codable, Sendable {
    var version = 1
    var currency: String
    var confirmedAt: Date
    var confirmedCash: Double
    var transactionBaseline: Double
    var positions: [Position] = []
    var events: [Event] = []
    struct Position: Codable, Sendable {
        var id: UUID
        var principal: Double
        var start: Date
        var returned = false
        var cancelled = false
        var opening: Bool
    }
    struct Event: Codable, Sendable {
        var id = UUID()
        var depositID: UUID?
        var kind: String
        var amount: Double
        var date: Date
        var recordedAt = Date()
        var before: Double?
        var after: Double?
    }
    static func decode(_ data: Data) throws -> Self {
        let state = try JSONDecoder().decode(Self.self, from: data)
        guard state.version == 1, state.currency.count == 3,
              state.confirmedCash.isFinite, state.transactionBaseline.isFinite,
              Set(state.positions.map(\.id)).count == state.positions.count,
              Set(state.events.map(\.id)).count == state.events.count,
              state.positions.allSatisfy({ $0.principal.isFinite && $0.principal >= 0 && $0.start.timeIntervalSince1970.isFinite }),
              state.events.allSatisfy({ $0.amount.isFinite && $0.date.timeIntervalSince1970.isFinite && ($0.before?.isFinite ?? true) && ($0.after?.isFinite ?? true) })
        else { throw CocoaError(.coderReadCorrupt) }
        return state
    }
    func encode() throws -> Data { try JSONEncoder().encode(self) }
    func movements(asOf date: Date) -> Double {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date)) ?? date
        return events.filter { $0.date < end }.reduce(0) { $0 + $1.amount }
    }
}

@MainActor enum MacLiquidity {
    static func profile(in context: ModelContext) throws -> FinancialProfile? {
        let profiles = try context.fetch(FetchDescriptor<FinancialProfile>(sortBy: [SortDescriptor(\.createdAt)])).filter { $0.deletedAt == nil }
        return profiles.first { $0.liquidityData != nil } ?? profiles.first
    }
    static func state(_ profile: FinancialProfile?) -> LiquidityState? {
        profile?.liquidityData.flatMap { try? LiquidityState.decode($0) }
    }
    static func net(_ transactions: [Transaction], currency: String, asOf date: Date = Date()) -> Double {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date)) ?? date
        return transactions.filter { $0.deletedAt == nil && $0.date < end && $0.baseCurrencyCode == currency && !($0.note ?? "").contains("[FTEstimated]") }
            .reduce(0) { $0 + ($1.typedType == .income ? $1.baseAmount : -$1.baseAmount) }
    }
    static func cash(_ state: LiquidityState, transactions: [Transaction], asOf date: Date = Date()) -> Double {
        FinancialPrecision.roundAmountForStorage(state.confirmedCash + net(transactions, currency: state.currency, asOf: date) - state.transactionBaseline + state.movements(asOf: date))
    }
    static func confirm(amount: Double, profile: FinancialProfile, currency: String, in context: ModelContext) throws {
        try MacRecoveryJournal.assertWritable(in: context)
        guard !MacAutomaticPosting.isRunning, amount.isFinite, abs(amount) <= 1e12 else { throw MacFinanceRecords.Failure.invalidTerm }
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        var value: LiquidityState
        if let data = profile.liquidityData {
            value = try LiquidityState.decode(data)
            guard value.currency == currency else { throw MacCurrency.Failure.mixedBooks }
            let before = cash(value, transactions: transactions)
            value.events.append(.init(depositID: nil, kind: "calibration", amount: amount - before, date: Date(), before: before, after: amount))
        } else {
            value = LiquidityState(currency: currency, confirmedAt: Date(), confirmedCash: amount, transactionBaseline: net(transactions, currency: currency))
            let deposits = try context.fetch(FetchDescriptor<DepositRecord>())
            for d in deposits where d.deletedAt == nil && d.baseCurrencyCode == currency {
                // Only an active contract or an identifiable estimated maturity
                // retains principal. Unknown ended history is never resurrected.
                let estimated = transactions.contains { $0.deletedAt == nil && ($0.note ?? "").contains("[FTDep:\(d.id.uuidString):") && ($0.note ?? "").contains("[FTEstimated]") && $0.date >= d.maturityDate }
                let rolled = deposits.contains { $0.deletedAt == nil && $0.sourceDepositID == d.id }
                guard d.isActive || (estimated && !rolled) else { continue }
                let future = Calendar.current.startOfDay(for: d.startDate) > Calendar.current.startOfDay(for: Date())
                value.positions.append(.init(id: d.id, principal: d.basePrincipal, start: d.startDate, opening: !future))
                if future { value.events.append(.init(depositID: d.id, kind: "fund", amount: -d.basePrincipal, date: d.startDate)) }
            }
        }
        profile.liquidityData = try value.encode()
    }
    /// Caller saves the deposit and profile together, on the single main context.
    static func register(_ deposit: DepositRecord, opening: Bool = false, in context: ModelContext) throws {
        guard let p = try profile(in: context), let data = p.liquidityData else { return }
        var s = try LiquidityState.decode(data)
        guard s.currency == deposit.baseCurrencyCode else { throw MacCurrency.Failure.mixedBooks }
        guard !s.positions.contains(where: { $0.id == deposit.id }) else { return }
        let alreadyHeld = opening && Calendar.current.startOfDay(for: deposit.startDate) <= Calendar.current.startOfDay(for: Date())
        s.positions.append(.init(id: deposit.id, principal: deposit.basePrincipal, start: deposit.startDate, opening: alreadyHeld))
        if !alreadyHeld { s.events.append(.init(depositID: deposit.id, kind: "fund", amount: -deposit.basePrincipal, date: deposit.startDate)) }
        p.liquidityData = try s.encode()
    }
    static func edit(_ deposit: DepositRecord, cancelling: Bool = false, in context: ModelContext) throws {
        guard let p = try profile(in: context), let data = p.liquidityData else { return }
        var s = try LiquidityState.decode(data)
        guard let i = s.positions.firstIndex(where: { $0.id == deposit.id }) else { return }
        let old = s.positions[i]
        guard !old.returned, !old.cancelled else { return }
        if cancelling {
            // Undo only an unreturned, newly funded contract. Deleting opening
            // history cannot be interpreted as proof of a bank payment.
            if !old.opening {
                let moves = Dictionary(grouping: s.events.filter { $0.depositID == deposit.id }, by: \.date)
                for (date, events) in moves { let sum = events.reduce(0) { $0 + $1.amount }; if abs(sum) > 1e-9 { s.events.append(.init(depositID: deposit.id, kind: "cancel", amount: -sum, date: date)) } }
            }
            s.positions[i].cancelled = true
        } else if old.principal != deposit.basePrincipal || old.start != deposit.startDate {
            if old.opening {
                s.events.append(.init(depositID: deposit.id, kind: "adjust", amount: old.principal - deposit.basePrincipal, date: Date()))
                // Opening principal is already held; do not schedule it away.
            } else {
                let moves = Dictionary(grouping: s.events.filter { $0.depositID == deposit.id }, by: \.date)
                for (date, events) in moves { let sum = events.reduce(0) { $0 + $1.amount }; if abs(sum) > 1e-9 { s.events.append(.init(depositID: deposit.id, kind: "reverse", amount: -sum, date: date)) } }
                s.events.append(.init(depositID: deposit.id, kind: "fund", amount: -deposit.basePrincipal, date: deposit.startDate))
            }
            s.positions[i].principal = deposit.basePrincipal
            s.positions[i].start = deposit.startDate
        }
        p.liquidityData = try s.encode()
    }
    static func pending(_ deposit: DepositRecord, profile: FinancialProfile?) -> Bool {
        state(profile)?.positions.contains { $0.id == deposit.id && !$0.returned && !$0.cancelled } ?? false
    }
    static func returnPrincipal(_ deposit: DepositRecord, in context: ModelContext) throws {
        guard let p = try profile(in: context), let data = p.liquidityData else { return }
        var s = try LiquidityState.decode(data)
        guard let i = s.positions.firstIndex(where: { $0.id == deposit.id }), !s.positions[i].returned, !s.positions[i].cancelled else { return }
        guard deposit.deletedAt == nil, Calendar.current.startOfDay(for: deposit.maturityDate) <= Calendar.current.startOfDay(for: Date()) else { throw MacFinanceReview.Failure.schedule }
        s.positions[i].returned = true
        s.events.append(.init(depositID: deposit.id, kind: "principalReturned", amount: s.positions[i].principal, date: Date()))
        p.liquidityData = try s.encode()
    }
    static func confirmPrincipal(_ deposit: DepositRecord, in context: ModelContext) throws {
        try MacRecoveryJournal.assertWritable(in: context)
        guard !MacAutomaticPosting.isRunning, !context.hasChanges,
              pending(deposit, profile: try profile(in: context)) else { throw MacFinanceReview.Failure.schedule }
        do { try returnPrincipal(deposit, in: context); try context.save() }
        catch { context.rollback(); throw error }
    }
}
