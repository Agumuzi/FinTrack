import Foundation
import Combine

/// App-owned, in-memory session: changing/dismissing views never persists a draft.
@MainActor
final class MacMenuBarSession: ObservableObject {
    let quickEntry = MacQuickEntryDraft()
    var onPageSelected: ((MacMenuBarPage) -> Void)?
    @Published var quickSettings = false
    @Published var page: MacMenuBarPage { didSet { onPageSelected?(page) } }
    @Published var amount = ""
    @Published var note = ""
    @Published var currency = "USD"
    @Published var category = "餐饮"
    @Published var income = false
    @Published var date = Date()
    @Published var continueAdding = false
    @Published var converterInput = ""
    @Published var converterCurrency = "USD"
    @Published var displayUnits = 1
    @Published var prototypeSaveCount = 0
    private var hasOpened = false

    init(configuration: MacAppEntryConfiguration) {
        page = configuration.pageMemory == .restart ? configuration.lastPage ?? configuration.defaultPage : configuration.defaultPage
    }

    func opened(configuration: MacAppEntryConfiguration) {
        if !hasOpened || configuration.pageMemory == .none {
            page = !hasOpened && configuration.pageMemory == .restart ? configuration.lastPage ?? configuration.defaultPage : configuration.defaultPage
        }
        hasOpened = true
    }
}
