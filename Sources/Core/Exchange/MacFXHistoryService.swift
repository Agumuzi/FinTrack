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
    var points: [MacFXHistoryPoint] = [] { didSet { plot = MacFXHistoryPlot(points) } }
    private(set) var plot = MacFXHistoryPlot([])
    var sourceName = ""
    var failedDays = 0
    var error: String?
    var fromCache = false
    var fetchedAt = Date()
    var completedDays = 0
    var totalDays = 0
    init(points: [MacFXHistoryPoint] = [], sourceName: String = "", failedDays: Int = 0, error: String? = nil,
         fromCache: Bool = false, fetchedAt: Date = Date(), completedDays: Int = 0, totalDays: Int = 0) {
        self.points = points; self.plot = MacFXHistoryPlot(points); self.sourceName = sourceName
        self.failedDays = failedDays; self.error = error; self.fromCache = fromCache
        self.fetchedAt = fetchedAt; self.completedDays = completedDays; self.totalDays = totalDays
    }
}

/// One linear pass per changed data snapshot, independent of SwiftUI redraws.
nonisolated struct MacFXHistoryPlot: Sendable {
    struct Point: Identifiable, Sendable {
        let day: String; let date: Date; let unitRate: Double; let segment: Int
        var id: String { day }
    }
    let points: [Point]
    let minimum: Double
    let maximum: Double
    init(_ raw: [MacFXHistoryPoint]) {
        var points: [Point] = [], segment = 0, previous: Date?
        var minimum = Double.greatestFiniteMagnitude, maximum = 0.0
        for point in raw where MacFXMath.validRate(point.unitRate) && point.unitRate < Double.greatestFiniteMagnitude / 400 {
            let date = point.date
            if let previous, date.timeIntervalSince(previous) > 3 * 86400 { segment += 1 }
            points.append(Point(day: point.day, date: date, unitRate: point.unitRate, segment: segment))
            minimum = min(minimum, point.unitRate); maximum = max(maximum, point.unitRate); previous = date
        }
        if points.count > 31 {
            self.points = (0..<31).map { points[Int((Double($0) * Double(points.count - 1) / 30).rounded())] }
        } else { self.points = points }
        self.minimum = points.isEmpty ? 0 : minimum; self.maximum = points.isEmpty ? 1 : maximum
    }
}

/// Separate from monitoring baselines and all accounting storage.
@MainActor
final class MacFXHistoryService: ObservableObject {
    static let storageKey = "v4_fx_chart_history_cache"
    static let legacyStorageKey = "v3_fx_chart_history_cache"
    private nonisolated struct Entry: Codable, Sendable {
        let pair: MacFXPair
        let sourceID: String
        let revision: String
        let point: MacFXHistoryPoint
        var key: String { pair.key + "/" + sourceID + "/" + revision + "/" + point.day }
    }
    private nonisolated struct Coverage: Codable, Sendable {
        let pair: MacFXPair
        let sourceID: String
        let revision: String
        let start: String
        let end: String
        let fetchedAt: Date
        func matches(_ r: MacFXHistoryRequest) -> Bool { pair == r.pair && sourceID == r.sourceID && revision == r.revision }
    }
    private nonisolated struct Stored: Codable, Sendable { var version = 4; let rows: [Entry]; let coverage: [Coverage] }
    private var saveVersion = 0
    private var coverage: [Coverage] = []
    @Published private(set) var results: [MacFXHistoryRequest: MacFXHistoryResult] = [:]
    @Published private(set) var loading: Set<MacFXHistoryRequest> = []
    private var entries: [String: Entry] = [:]
    private var tasks: [MacFXHistoryRequest: Task<MacFXHistoryResult, Never>] = [:]
    private var jobIDs: [MacFXHistoryRequest: UUID] = [:]
    private var waiters: [MacFXHistoryRequest: Set<UUID>] = [:]
    private var now: () -> Date
    private var persist: (Data) -> Void

    private var restoration: Task<Stored, Never>?
    init(data: Data? = nil, legacyData: Data? = nil, now: @escaping () -> Date = Date.init, persist: @escaping (Data) -> Void = { _ in }) {
        self.now = now; self.persist = persist
        let clock = now(), payloads = [legacyData, data].compactMap { $0 }
        restoration = Task.detached(priority: .userInitiated) {
            var entries: [String: Entry] = [:], coverage: [Coverage] = []
            for data in payloads where data.count <= 8 * 1024 * 1024 {
                let stored = try? JSONDecoder().decode(Stored.self, from: data)
                let rows = stored?.version == 4 ? stored?.rows : try? JSONDecoder().decode([Entry].self, from: data)
                guard let rows, rows.count <= 12000 else { continue }
                for row in rows where MacFXDates.day(row.point.day) != nil && MacFXMath.validRate(row.point.unitRate)
                    && row.point.retrievedAt <= clock.addingTimeInterval(300) && !row.sourceID.isEmpty && !row.revision.isEmpty {
                    if case .day(let day, let zone) = row.point.quoteTime {
                        guard day == row.point.day, let timeZone = TimeZone(identifier: zone) else { continue }
                        var calendar = MacFXDates.utc; calendar.timeZone = timeZone
                        guard day <= MacFXDates.tag(clock, calendar: calendar) else { continue }
                    } else if let instant = MacFXDates.instant(row.point.quoteTime) {
                        guard instant <= clock.addingTimeInterval(300) else { continue }
                    } else { continue }
                    entries[row.key] = row
                }
                coverage = Array((stored?.coverage ?? []).filter { MacFXDates.day($0.start) != nil && MacFXDates.day($0.end) != nil && $0.start <= $0.end && $0.fetchedAt <= clock.addingTimeInterval(300) }.suffix(80))
            }
            if entries.count > 12000 {
                entries = Dictionary(uniqueKeysWithValues: entries.values.sorted { $0.point.retrievedAt > $1.point.retrievedAt }.prefix(12000).map { ($0.key, $0) }); coverage = []
            }
            return Stored(rows: Array(entries.values), coverage: coverage)
        }
        // Begin restoring at application startup, before a chart is expanded.
        Task { [weak self] in await self?.restore() }
    }
    func restore() async {
        guard let task = restoration else { return }
        let stored = await task.value
        guard restoration != nil else { return }
        restoration = nil
        entries = Dictionary(uniqueKeysWithValues: stored.rows.map { ($0.key, $0) }); coverage = stored.coverage
    }
    /// Synchronous cache projection used by the very first chart body.
    func result(for request: MacFXHistoryRequest) -> MacFXHistoryResult? {
        if let result = results[request], !result.points.isEmpty || result.error != nil { return result }
        let start = request.range.days(endingAt: request.endingDay).first ?? request.endingDay
        var rows = entries.values.filter { $0.pair == request.pair && $0.sourceID == request.sourceID && $0.revision == request.revision && $0.point.day >= start && $0.point.day <= request.endingDay }
        var name = request.sourceID == "system.cbr" ? "CBR" : request.sourceID == "system.ecb" ? "ECB" : "历史参考"
        if rows.isEmpty {
            // Never merge old Currency API points into an ECB/CBR-labelled line.
            rows = entries.values.filter { $0.pair == request.pair && $0.sourceID == "free" && $0.revision == "currency-api-v1-utc-publication-day" && $0.point.day >= start && $0.point.day <= request.endingDay }
            name = "Currency API · 旧缓存"
        }
        guard !rows.isEmpty else { return results[request] }
        return MacFXHistoryResult(points: rows.map(\.point).sorted { $0.day < $1.day }, sourceName: name, fromCache: true, fetchedAt: rows.map { $0.point.retrievedAt }.min() ?? now())
    }
    func request(pair: MacFXPair, range: MacFXHistoryRange, monitor: MacFXMonitor) -> MacFXHistoryRequest? {
        guard let provider = monitor.historyProvider(pair) else { return nil }
        // A publication date is a day, not a local-midnight instant.
        let end = MacFXDates.tag(now(), calendar: provider.dayCalendar)
        return MacFXHistoryRequest(pair: pair, range: range, sourceID: provider.id, revision: provider.revision, endingDay: end)
    }
    func load(_ request: MacFXHistoryRequest, monitor: MacFXMonitor) async {
        await restore()
        guard !Task.isCancelled else { return }
        if let result = results[request], !loading.contains(request), result.totalDays > 0,
           result.completedDays == result.totalDays,
           now().timeIntervalSince(result.fetchedAt) < (result.failedDays > 0 ? 300 : 3600) { return }
        let task: Task<MacFXHistoryResult, Never>, job: UUID
        if let existing = tasks[request], !existing.isCancelled, let id = jobIDs[request] { task = existing; job = id }
        else {
            // Only the visible chart is useful. A new range/pair never queues
            // behind an invisible range that the user has already dismissed.
            for (key, previous) in tasks where key != request && key.pair == request.pair { previous.cancel() }
            job = UUID(); jobIDs[request] = job; loading.insert(request)
            task = Task { [weak self] in
                guard let self else { return MacFXHistoryResult() }
                return await self.perform(request, monitor: monitor, job: job)
            }
            tasks[request] = task
        }
        let waiter = UUID(); waiters[request, default: []].insert(waiter)
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { @MainActor [weak self] in self?.release(waiter, request: request, job: job) }
        }
        release(waiter, request: request, job: job, cancelIfUnused: false)
        guard jobIDs[request] == job else { return }
        if !task.isCancelled { results[request] = result }
        tasks[request] = nil; jobIDs[request] = nil; waiters[request] = nil; loading.remove(request)
        // UI result snapshots are bounded independently of day-point storage.
        if results.count > 40, let oldest = results.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key { results.removeValue(forKey: oldest) }
    }
    private func release(_ waiter: UUID, request: MacFXHistoryRequest, job: UUID, cancelIfUnused: Bool = true) {
        guard jobIDs[request] == job, waiters[request]?.remove(waiter) != nil else { return }
        if cancelIfUnused, waiters[request]?.isEmpty == true { tasks[request]?.cancel() }
    }
    private struct Outcome: Sendable { var point: MacFXHistoryPoint?; var error: String?; var cached = false }
    private func perform(_ request: MacFXHistoryRequest, monitor: MacFXMonitor, job: UUID) async -> MacFXHistoryResult {
        if monitor.supportsRange(request) {
            return await performRange(request, monitor: monitor, job: job)
        }
        return await performDaily(request, monitor: monitor, job: job)
    }
    private func performDaily(_ request: MacFXHistoryRequest, monitor: MacFXMonitor, job: UUID) async -> MacFXHistoryResult {
        let days = request.range.days(endingAt: request.endingDay), cycle = "chart-" + UUID().uuidString
        var result = MacFXHistoryResult(sourceName: monitor.providerList().first { $0.id == request.sourceID }?.name ?? "历史参考", fromCache: true, fetchedAt: now())
        result.totalDays = days.count
        var collected: [String: MacFXHistoryPoint] = [:]
        for day in days {
            let key = request.pair.key + "/" + request.sourceID + "/" + request.revision + "/" + day
            if let entry = entries[key] { collected[day] = entry.point }
        }
        result.points = collected.values.sorted { $0.day < $1.day }
        if jobIDs[request] == job { results[request] = result }
        // A rolling window reuses each free slot immediately; completed points
        // are published incrementally instead of waiting for a whole month.
        await withTaskGroup(of: Outcome.self) { group in
            var pending = days.reversed().makeIterator()
            for _ in 0..<2 { if let day = pending.next() { group.addTask { await self.point(day, request: request, monitor: monitor, cycle: cycle) } } }
            while let outcome = await group.next() {
                guard !Task.isCancelled else { group.cancelAll(); break }
                result.completedDays += 1
                if let point = outcome.point { collected[point.day] = point; result.fromCache = result.fromCache && outcome.cached }
                if let error = outcome.error { result.failedDays += 1; result.error = result.error ?? error }
                result.points = collected.values.sorted { $0.day < $1.day }
                if result.completedDays == 1 || result.completedDays % 8 == 0, jobIDs[request] == job { results[request] = result }
                if let day = pending.next() { group.addTask { await self.point(day, request: request, monitor: monitor, cycle: cycle) } }
            }
        }
        result.points.sort { $0.day < $1.day }
        if result.points.isEmpty { result.fromCache = false }
        if entries.count > 12000 {
            entries = Dictionary(uniqueKeysWithValues: entries.values.sorted { $0.point.retrievedAt > $1.point.retrievedAt }.prefix(12000).map { ($0.key, $0) }); coverage = []
        }
        await save()
        return result
    }
    private func save() async {
        saveVersion += 1; let version = saveVersion
        let snapshot = Stored(rows: Array(entries.values), coverage: coverage)
        let data = await Task.detached(priority: .utility) { try? JSONEncoder().encode(snapshot) }.value
        if saveVersion == version, let data, data.count <= 8 * 1024 * 1024 { persist(data) }
    }
    private func performRange(_ request: MacFXHistoryRequest, monitor: MacFXMonitor, job: UUID) async -> MacFXHistoryResult {
        let start = request.range.days(endingAt: request.endingDay).first ?? request.endingDay
        func shifted(_ day: String, _ offset: Int) -> String {
            MacFXDates.day(day).flatMap { MacFXDates.utc.date(byAdding: .day, value: offset, to: $0) }.map { MacFXDates.tag($0, calendar: MacFXDates.utc) } ?? day
        }
        let recentBoundary = shifted(MacFXDates.tag(now(), calendar: MacFXDates.utc), -3)
        let spans = coverage.filter { $0.matches(request) }.map { span in
            (span.start, now().timeIntervalSince(span.fetchedAt) < 12 * 3600 ? span.end : min(span.end, recentBoundary))
        }.filter { $0.0 <= $0.1 }.sorted { $0.0 < $1.0 }
        var cursor = start, missing: [(String, String)] = []
        for (first, last) in spans where last >= cursor && first <= request.endingDay {
            if first > cursor { missing.append((cursor, min(request.endingDay, shifted(first, -1)))) }
            cursor = max(cursor, shifted(last, 1))
            if cursor > request.endingDay { break }
        }
        if cursor <= request.endingDay { missing.append((cursor, request.endingDay)) }
        let covered = missing.isEmpty
        var result = result(for: request) ?? MacFXHistoryResult()
        result.totalDays = request.range.rawValue
        if covered { result.completedDays = result.totalDays; result.fromCache = true; result.fetchedAt = now(); return result }
        if results[request] == nil { results[request] = result }
        do {
            for (fetchStart, fetchEnd) in missing {
                let points = try await monitor.historyRange(request, start: fetchStart, end: fetchEnd)
                // Persist only verifiable points; queried non-publication days
                // are represented by coverage, never copied/zero-valued quotes.
                let valid = points.filter { point in
                    guard point.day >= fetchStart, point.day <= fetchEnd, MacFXMath.validRate(point.unitRate), point.retrievedAt <= now().addingTimeInterval(300) else { return false }
                    if case .day(let day, let zone) = point.quoteTime { return day == point.day && TimeZone(identifier: zone) != nil }
                    return false
                }
                guard valid.count == points.count else { throw MacFXNetworkFailure.invalid }
                for point in valid {
                    let entry = Entry(pair: request.pair, sourceID: request.sourceID, revision: request.revision, point: point)
                    entries[entry.key] = entry
                }
            }
            coverage.removeAll { $0.matches(request) && $0.start >= start && $0.end <= request.endingDay }
            coverage.append(Coverage(pair: request.pair, sourceID: request.sourceID, revision: request.revision, start: start, end: request.endingDay, fetchedAt: now()))
            coverage = Array(coverage.suffix(80))
            if entries.count > 12000 { entries = Dictionary(uniqueKeysWithValues: entries.values.sorted { $0.point.retrievedAt > $1.point.retrievedAt }.prefix(12000).map { ($0.key, $0) }); coverage = [] }
            // Use only this source's raw points; the legacy preview is replaced.
            result.points = entries.values.filter { $0.pair == request.pair && $0.sourceID == request.sourceID && $0.revision == request.revision && $0.point.day >= start && $0.point.day <= request.endingDay }.map(\.point).sorted { $0.day < $1.day }
            result.sourceName = request.sourceID == "system.cbr" ? "CBR" : request.sourceID == "system.ecb" ? "ECB" : "Frankfurter · ECB"
            result.fromCache = false; result.error = nil; result.failedDays = 0
            await save()
        } catch {
            // Only an unsupported/invalid range can fall back to the same
            // provider's bounded day API. Transport failures and rate limits
            // never fan out into dozens of retries or overwrite a valid cache.
            if result.points.isEmpty, case MacFXNetworkFailure.invalid = error, !Task.isCancelled {
                return await performDaily(request, monitor: monitor, job: job)
            }
            // Keep the exact old snapshot on error; a failure is never a zero.
            result.error = error.localizedDescription; result.failedDays = 1
        }
        result.completedDays = result.totalDays; result.fetchedAt = now()
        return result
    }
    private func point(_ day: String, request: MacFXHistoryRequest, monitor: MacFXMonitor, cycle: String) async -> Outcome {
        let key = request.pair.key + "/" + request.sourceID + "/" + request.revision + "/" + day
        guard !Task.isCancelled else { return Outcome() }
        // Recent publication days can still be corrected. Older daily points
        // are immutable for this source revision and need no daily re-download.
        let recent = MacFXDates.day(day).map { now().timeIntervalSince($0) < 2 * 86400 } ?? true
        if let entry = entries[key], !recent || now().timeIntervalSince(entry.point.retrievedAt) < 3600 { return Outcome(point: entry.point, cached: true) }
        do {
            let point = try await monitor.historyPoint(pair: request.pair, day: day, sourceID: request.sourceID, revision: request.revision, cycle: cycle)
            guard !Task.isCancelled else { return Outcome() }
            let entry = Entry(pair: request.pair, sourceID: request.sourceID, revision: request.revision, point: point)
            entries[key] = entry
            return Outcome(point: point)
        } catch {
            if Task.isCancelled { return Outcome() }
            return Outcome(point: entries[key]?.point, error: error.localizedDescription, cached: entries[key] != nil)
        }
    }
}
