import Foundation
import Combine

nonisolated enum MacFXHistoryRange: Int, CaseIterable, Codable, Identifiable, Sendable {
    case week = 7, month = 30, quarter = 90, halfYear = 180, year = 365
    var id: Int { rawValue }
    var title: String { switch self { case .week: "7天"; case .month: "1月"; case .quarter: "3月"; case .halfYear: "6月"; case .year: "1年" } }
    func days(endingAt end: String) -> [String] {
        guard let last = MacFXDates.day(end) else { return [] }
        let count = min(31, rawValue)
        return (0..<count).compactMap { index in
            let offset = -Int((Double(rawValue - 1) * Double(count - 1 - index) / Double(count - 1)).rounded())
            return MacFXDates.utc.date(byAdding: .day, value: offset, to: last).map { MacFXDates.tag($0, calendar: MacFXDates.utc) }
        }
    }
}

nonisolated struct MacFXHistoryPoint: Codable, Sendable {
    let day: String
    let unitRate: Double
    let quoteTime: MacFXQuoteTime
    let retrievedAt: Date
    var date: Date { MacFXDates.day(day) ?? .distantPast }
}

nonisolated struct MacFXHistoryRequest: Hashable, Sendable {
    let pair: MacFXPair
    let range: MacFXHistoryRange
    let sourceID: String
    let revision: String
    let endingDay: String
}

nonisolated struct MacFXHistoryResult: Sendable {
    var points: [MacFXHistoryPoint] = []
    var sourceName = ""
    var failedDays = 0
    var error: String?
    var fromCache = false
    var fetchedAt = Date()
}

/// Separate from monitoring baselines and all accounting storage.
@MainActor
final class MacFXHistoryService: ObservableObject {
    static let storageKey = "v3_fx_chart_history_cache"
    private struct Entry: Codable {
        let pair: MacFXPair
        let sourceID: String
        let revision: String
        let point: MacFXHistoryPoint
        var key: String { pair.key + "/" + sourceID + "/" + revision + "/" + point.day }
    }
    @Published private(set) var results: [MacFXHistoryRequest: MacFXHistoryResult] = [:]
    @Published private(set) var loading: Set<MacFXHistoryRequest> = []
    private var entries: [String: Entry] = [:]
    private var tasks: [MacFXHistoryRequest: Task<MacFXHistoryResult, Never>] = [:]
    private var tail: Task<Void, Never>?
    private var now: () -> Date
    private var persist: (Data) -> Void

    init(data: Data? = nil, now: @escaping () -> Date = Date.init, persist: @escaping (Data) -> Void = { _ in }) {
        self.now = now; self.persist = persist
        if let data, let rows = try? JSONDecoder().decode([Entry].self, from: data), rows.count <= 2400 {
            for row in rows where MacFXDates.day(row.point.day) != nil && MacFXMath.validRate(row.point.unitRate)
                && row.point.retrievedAt <= now().addingTimeInterval(300) && !row.sourceID.isEmpty && !row.revision.isEmpty {
                entries[row.key] = row
            }
        }
    }
    func request(pair: MacFXPair, range: MacFXHistoryRange, monitor: MacFXMonitor) -> MacFXHistoryRequest? {
        guard let provider = monitor.historyProvider(pair) else { return nil }
        // A publication date is a day, not a local-midnight instant.
        let end = MacFXDates.tag(now(), calendar: provider.dayCalendar)
        return MacFXHistoryRequest(pair: pair, range: range, sourceID: provider.id, revision: provider.revision, endingDay: end)
    }
    func load(_ request: MacFXHistoryRequest, monitor: MacFXMonitor) async {
        if let result = results[request], now().timeIntervalSince(result.fetchedAt) < (result.failedDays > 0 ? 300 : 3600) { return }
        if let task = tasks[request] { _ = await task.value; return }
        let preceding = tail
        loading.insert(request)
        let task = Task { [weak self] in
            await preceding?.value
            guard let self else { return MacFXHistoryResult() }
            return await self.perform(request, monitor: monitor)
        }
        tasks[request] = task
        tail = Task { _ = await task.value }
        let result = await task.value
        results[request] = result
        tasks[request] = nil
        loading.remove(request)
        // UI result snapshots are bounded independently of day-point storage.
        if results.count > 40, let oldest = results.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key { results.removeValue(forKey: oldest) }
    }
    private struct Outcome { var point: MacFXHistoryPoint?; var error: String?; var cached = false }
    private func perform(_ request: MacFXHistoryRequest, monitor: MacFXMonitor) async -> MacFXHistoryResult {
        let days = request.range.days(endingAt: request.endingDay), cycle = "chart-" + UUID().uuidString
        var result = MacFXHistoryResult(sourceName: monitor.providerList().first { $0.id == request.sourceID }?.name ?? "历史参考", fromCache: true, fetchedAt: now())
        // All range jobs share a queue; at most two history dates run at once.
        for start in stride(from: 0, to: days.count, by: 2) {
            async let first = point(days[start], request: request, monitor: monitor, cycle: cycle)
            async let second = optionalPoint(start + 1 < days.count ? days[start + 1] : nil, request: request, monitor: monitor, cycle: cycle)
            let outcomes = await [first, second]
            for outcome in outcomes.compactMap({ $0 }) {
                if let point = outcome.point { result.points.append(point); result.fromCache = result.fromCache && outcome.cached }
                if let error = outcome.error { result.failedDays += 1; result.error = result.error ?? error }
            }
        }
        result.points.sort { $0.day < $1.day }
        if result.points.isEmpty { result.fromCache = false }
        if entries.count > 2400 {
            entries = Dictionary(uniqueKeysWithValues: entries.values.sorted { $0.point.retrievedAt > $1.point.retrievedAt }.prefix(2400).map { ($0.key, $0) })
        }
        if let data = try? JSONEncoder().encode(Array(entries.values)) { persist(data) }
        return result
    }
    private func optionalPoint(_ day: String?, request: MacFXHistoryRequest, monitor: MacFXMonitor, cycle: String) async -> Outcome? {
        guard let day else { return nil }
        return await point(day, request: request, monitor: monitor, cycle: cycle)
    }
    private func point(_ day: String, request: MacFXHistoryRequest, monitor: MacFXMonitor, cycle: String) async -> Outcome {
        let key = request.pair.key + "/" + request.sourceID + "/" + request.revision + "/" + day
        if let entry = entries[key], now().timeIntervalSince(entry.point.retrievedAt) < 86400 { return Outcome(point: entry.point, cached: true) }
        do {
            let point = try await monitor.historyPoint(pair: request.pair, day: day, sourceID: request.sourceID, revision: request.revision, cycle: cycle)
            let entry = Entry(pair: request.pair, sourceID: request.sourceID, revision: request.revision, point: point)
            entries[key] = entry
            return Outcome(point: point)
        } catch {
            return Outcome(point: entries[key]?.point, error: error.localizedDescription, cached: entries[key] != nil)
        }
    }
}
