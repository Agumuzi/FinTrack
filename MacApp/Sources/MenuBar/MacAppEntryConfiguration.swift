import Foundation

/// One atomic preference; never apply the two entry switches independently.
struct MacAppEntryConfiguration: Codable, Equatable {
    static let storageKey = "v3_app_entries"
    var version = 1
    var showMenuBar = true
    var showDock = true
    var showMainOnLaunch = true
    var defaultPage = MacMenuBarPage.quickEntry
    var pageMemory = MacMenuBarPageMemory.runtime
    var lastPage: MacMenuBarPage?
    var iconStyle = MacMenuIconStyle.application
    var information = MacMenuInformation.icon
    var displayPair: MacFXPair?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, default fallback: T) throws -> T {
            c.contains(key) ? try c.decode(T.self, forKey: key) : fallback
        }
        version = try read(.version, default: 1)
        guard version == 1 else { throw DecodingError.dataCorruptedError(forKey: .version, in: c, debugDescription: "Unsupported entry configuration") }
        showMenuBar = try read(.showMenuBar, default: true)
        showDock = try read(.showDock, default: true)
        showMainOnLaunch = try read(.showMainOnLaunch, default: true)
        defaultPage = MacMenuBarPage(rawValue: try read(.defaultPage, default: "")) ?? .quickEntry
        pageMemory = MacMenuBarPageMemory(rawValue: try read(.pageMemory, default: "")) ?? .runtime
        lastPage = MacMenuBarPage(rawValue: try c.decodeIfPresent(String.self, forKey: .lastPage) ?? "")
        iconStyle = MacMenuIconStyle(rawValue: try read(.iconStyle, default: "")) ?? .application
        information = MacMenuInformation(rawValue: try read(.information, default: "")) ?? .icon
        displayPair = try c.decodeIfPresent(MacFXPair.self, forKey: .displayPair)
        self = normalized()
    }

    func normalized() -> Self {
        var result = self
        if !showMenuBar && !showDock { result.showMenuBar = true; result.showDock = true }
        if !result.showMenuBar { result.showMainOnLaunch = true }
        if result.pageMemory != .restart { result.lastPage = nil }
        return result
    }

    static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: storageKey), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value.normalized()
    }
}

enum MacMenuBarPage: String, Codable, CaseIterable, Identifiable {
    case quickEntry, rates, converter
    var id: String { rawValue }
    var title: String { switch self { case .quickEntry: "快速记账"; case .rates: "汇率列表"; case .converter: "汇率换算" } }
    var symbol: String { switch self { case .quickEntry: "square.and.pencil"; case .rates: "chart.line.uptrend.xyaxis"; case .converter: "arrow.left.arrow.right" } }
}

enum MacMenuBarPageMemory: String, Codable, CaseIterable {
    case none, runtime, restart
    var title: String { switch self { case .none: "不记忆"; case .runtime: "本次运行内"; case .restart: "跨重启" } }
}
