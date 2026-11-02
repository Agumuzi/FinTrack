import SwiftUI
import SwiftData

/// Mac-native keyboard/editor for the ORIGINAL Transaction schema.
/// Unlike the iOS custom numeric keyboard, uses standard TextField + DatePicker.
/// Original currency and dated exchange rates are preserved in each snapshot.
struct MacTransactionEditor: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("v2_category_styles") private var categoryStyleRevision = Data()
    @Query(sort: \FinTrackMac.Category.createdAt) private var categories: [FinTrackMac.Category]

    let bookCurrency: String
    let existing: Transaction?
    var onSaved: ((UUID) -> Void)?

    @State private var type: TransactionType = .expense
    @State private var amountText = ""
    @State private var category = ""
    @State private var categoryUsage = MacCategoryUsageSnapshot()
    @State private var note = ""
    @State private var date = Date()
    @State private var originalCurrency = ""
    @State private var customCurrency = false
    @State private var rateText = "1"
    @State private var fetchingRate = false
    @State private var rateRequest = UUID()
    @State private var useBankAmount = false
    @State private var bankAmount = ""
    @State private var quoteMessage: String?
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var keepAdding = false
    @State private var showsExchangeDetails = false
    @State private var showsDatePicker = false
    @State private var managingCategories = false
    @State private var managedCategoryID: UUID?
    @State private var savedMessage: String?
    @FocusState private var amountFocused: Bool
    @FocusState private var entryDateFocused: Bool

    private var sameCurrencyEditable: Bool {
        guard let existing else { return true }
        return existing.baseCurrencyCode == bookCurrency
            && !MacTransactionCRUD.isProtectedGeneratedPosting(existing)
    }

    private var savedCategories: [String] {
        var seen = Set<String>()
        return categoryUsage.sorted(categories.filter { $0.deletedAt == nil && $0.type == type.rawValue })
            .filter { seen.insert($0.name).inserted }.map(\.name)
    }

    private var foreignCurrency: Bool { originalCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() != bookCurrency }
    private var currencyChoices: [String] {
        let configured: [String] = MacSettingsStore.load("v2_currencies", fallback: [])
        return Array(Set(configured + [bookCurrency, originalCurrency.uppercased()])).filter { (try? MacCurrency.code($0)) != nil }.sorted()
    }
    private var candidateSnapshot: MacCurrencySnapshot? {
        guard let amount = try? MacTransactionCRUD.amount(amountText) else { return nil }
        if foreignCurrency && useBankAmount { return try? MacBankSettlement.snapshot(originalAmount:amount,actualBaseAmount:MacTransactionCRUD.amount(bankAmount),original:originalCurrency,base:bookCurrency) }
        return try? MacCurrency.snapshot(amount:amount,original:originalCurrency,base:bookCurrency,rate:foreignCurrency ? MacCurrency.rate(rateText) : 1)
    }
    private var convertedAmount: String? {
        candidateSnapshot.map { MacDisplayPreferences.money($0.baseAmount, decimals:2) + " " + bookCurrency }
    }
    private var editableBaseAmount: Binding<String> {
        Binding(get: {
            if useBankAmount { return bankAmount }
            return candidateSnapshot.map { MacBankSettlement.amountText($0.baseAmount) } ?? ""
        },set:{ value in
            rateRequest = UUID(); fetchingRate = false; quoteMessage = nil
            bankAmount = value; useBankAmount = true
        })
    }
    private var editableRate: Binding<String> {
        Binding(get: {
            if useBankAmount { return candidateSnapshot.map { MacBankSettlement.rateText($0.rate) } ?? "" }
            return rateText
        },set:{ value in
            rateRequest = UUID(); fetchingRate = false; quoteMessage = nil
            rateText = value; useBankAmount = false
        })
    }
    private var saveColor: Color { MacUI.accent }

    var body: some View {
        let _ = categoryStyleRevision
        MacFormShell(width: 560) {
            VStack(alignment: .leading, spacing: MacUI.space(16)) {
            HStack {
                Text(existing == nil ? L10n.text("mac.transactionEditor.MacFormShell.61a6ed6623") : L10n.text("mac.transactionEditor.MacFormShell.eabdc2aa39")).appFont(.dialogTitle, weight: .bold, design: .default).accessibilityIdentifier("editorTitle")
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").appIconFont(19, weight: .medium, design: .default).foregroundStyle(.secondary).frame(width: MacUI.space(30), height: MacUI.space(30)).contentShape(Rectangle()) }
                    .buttonStyle(MacInteractiveButtonStyle()).appHelp(L10n.text("mac.transactionEditor.MacFormShell.3fd47edce4")).accessibilityLabel(L10n.text("mac.transactionEditor.MacFormShell.8545c7685f")).accessibilityIdentifier("closeEntry")
            }
            MacEntryTypeSwitcher(type:Binding(get:{type},set:{value in
                if type != value { type = value; category = ""; savedMessage = nil }
            }),prefix:"entry")

            }
        } fields: {
                VStack(alignment: .leading, spacing: MacUI.space(16)) {
                    if !sameCurrencyEditable {
                        Text("This record requires reconciliation before editing.").foregroundStyle(.red).accessibilityIdentifier("foreignEditBlocked")
                    }
                    ViewThatFits(in:.horizontal) {
                        HStack(alignment:.top,spacing:14) {amountInput.frame(minWidth:MacNumberInput.minimumEditingWidth(large:true));currencyInput}
                        VStack(alignment:.leading,spacing:14) {amountInput;currencyInput}
                    }
                    field(L10n.text("mac.transactionEditor.field.515559957f")) {
                        HStack(spacing: MacUI.space(12)) {
                            HStack(spacing: MacUI.space(10)) {
                                if category.isEmpty { Image(systemName: "tag").foregroundStyle(.orange).frame(width: MacUI.space(30)) }
                                else { MacCategoryBadge(name: category, type: type.rawValue, size: 32) }
                                TextField(L10n.text("mac.transactionEditor.field.b4c9ab1131"), text: Binding(get: { MacOverviewStyle.category(category) }, set: { category = $0 })).textFieldStyle(.plain).appFont(.body, weight: .semibold, design: .default)
                                    .accessibilityLabel(L10n.text("mac.transactionEditor.field.515559957f")).accessibilityIdentifier("entryCategory")
                                MacIconMenu(selection: $category, options: savedCategories.map { item in
                                    MacIconMenuOption(title: MacOverviewStyle.category(item), value: item,
                                        image: MacCategoryCatalog.menuImage(style: MacCategoryCatalog.style(name: item, type: type.rawValue), name: item))
                                }, identifier: "savedCategoryMenu", accessibilityTitle: L10n.text("mac.transactionEditor.MacIconMenu.53285bb825"), width: 250, compact: true).disabled(savedCategories.isEmpty)
                            }.appPadding(.horizontal, 12).appMinHeight(40).modifier(MacEntryFieldBorder())
                            Button {
                                managedCategoryID = categories.first { ($0.name == category || MacOverviewStyle.category($0.name) == category) && $0.type == type.rawValue && $0.deletedAt == nil }?.id
                                managingCategories = true
                            } label: {
                                HStack(alignment: .center, spacing: MacUI.space(8)) {
                                    Image(systemName: "gearshape")
                                    Text(L10n.text("mac.transactionEditor.field.ee46fd8708")).fixedSize(horizontal: false, vertical: true)
                                }.appFont(.body, weight: .semibold).appPadding(.horizontal, 10)
                                    .frame(width: MacUI.space(154)).appMinHeight(44)
                                    .background(MacOverviewStyle.filters, in: RoundedRectangle(cornerRadius: 9))
                            }
                                .buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("entryManageCategories")
                        }
                    }
                    field(L10n.text("mac.transactionEditor.field.a12bdb393d")) {
                        Button { showsDatePicker = true } label: {
                            HStack(spacing: MacUI.space(12)) {
                                Image(systemName: "calendar").appIconFont(22, weight: .regular, design: .default)
                                Text(entryDateLabel).appFont(.body, weight: .semibold, design: .default)
                                Spacer(); Image(systemName: "chevron.down").appFont(.body, weight: .semibold, design: .default)
                            }.appPadding(.horizontal, 15).appMinHeight(40).modifier(MacEntryFieldBorder())
                        }.buttonStyle(MacInteractiveButtonStyle()).focused($entryDateFocused).accessibilityIdentifier("entryDate")
                            .accessibilityLabel(L10n.text("mac.transactionEditor.field.2e7f382ee4")).accessibilityValue(entryDateLabel)
                            .popover(isPresented: $showsDatePicker) {
                                MacCalendarPickerPopover(
                                    title: L10n.text("mac.transactionEditor.MacCalendarPickerPopover.680c78ec60"),
                                    selection: $date,
                                    pickerIdentifier: "entryDatePicker",
                                    doneIdentifier: "entryDateDone",
                                    onDone: { showsDatePicker = false }
                                )
                            }
                    }
                    field(L10n.text("mac.transactionEditor.field.b405227c7e")) {
                        HStack(alignment: .top, spacing: MacUI.space(11)) {
                            Image(systemName: "doc.text").appIconFont(23, weight: .regular, design: .default).appPadding(.top, 2)
                            TextField(L10n.text("mac.transactionEditor.field.f1d3bd51b9"), text: $note, axis: .vertical).textFieldStyle(.plain)
                                .lineLimit(2...3).appFont(.body, weight: .regular, design: .default).accessibilityLabel(L10n.text("mac.transactionEditor.field.daede98817")).accessibilityIdentifier("entryNote")
                            Text(L10n.format("mac.transactionEditor.field.005b8c90eb", Int64(note.count))).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).monospacedDigit().appPadding(.top, 3)
                        }.appPadding(14).frame(minHeight: MacUI.space(58), alignment: .top).modifier(MacEntryFieldBorder())
                    }
                    MacEntryExchangeCard(expanded:$showsExchangeDetails,source:originalCurrency,base:bookCurrency,identifier:"entryExchangeDetails") {
                            Text(L10n.format("mac.transactionEditor.MacEntryExchangeCard.f93d3198b7", "\(bookCurrency)")).appFont(.body, weight: .regular, design: .default).foregroundStyle(.secondary)
                            if foreignCurrency {
                                HStack(spacing: MacUI.space(10)) {
                                    Text("1 " + originalCurrency.uppercased() + " =")
                                    TextField(L10n.text("mac.transactionEditor.MacEntryExchangeCard.77a1126316"),text:editableRate).textFieldStyle(.roundedBorder).accessibilityIdentifier("entryExchangeRate")
                                    Text(bookCurrency)
                                    Button(L10n.text("mac.transactionEditor.MacEntryExchangeCard.18f1e2e636")) { fetchRate() }.accessibilityIdentifier("fetchEntryRate").disabled(fetchingRate)
                                }.appFont(.body,weight:.regular)
                                HStack {
                                    Text(L10n.text("mac.transactionEditor.MacEntryExchangeCard.85fbecc157") + bookCurrency)
                                    TextField(L10n.text("mac.transactionEditor.MacEntryExchangeCard.90d0bca859"),text:editableBaseAmount).textFieldStyle(.roundedBorder).accessibilityIdentifier("entryBankAmount")
                                }.appFont(.body,weight:.regular)
                                if useBankAmount {
                                    HStack {
                                        Text(L10n.text("mac.transactionEditor.MacEntryExchangeCard.3afb2bc588")).appFont(.caption,weight:.regular).foregroundStyle(.secondary)
                                        Spacer()
                                        Button(L10n.text("mac.transactionEditor.MacEntryExchangeCard.28ee63c2b0")) { useBankAmount = false }.accessibilityIdentifier("entryResetBankAmount")
                                    }
                                } else { Text(L10n.text("mac.transactionEditor.MacEntryExchangeCard.687d341a93")).appFont(.caption,weight:.regular).foregroundStyle(.secondary) }
                            }
                            Text(L10n.text("mac.transactionEditor.MacEntryExchangeCard.0e8f29c0ac") + (convertedAmount ?? L10n.text("mac.transactionEditor.MacEntryExchangeCard.bebaa80420"))).appFont(.body, weight: .medium, design: .default).accessibilityIdentifier("entryConvertedAmount")
                            if let quoteMessage { Text(quoteMessage).appFont(.caption, weight: .regular).foregroundStyle(.secondary) }
                    }
                    if let savedMessage { Text(savedMessage).appFont(.body, weight: .regular, design: .default).foregroundStyle(.green).accessibilityIdentifier("entrySavedMessage") }
                }.appPadding(.vertical, 2).appPadding(.horizontal, 2)
                    .disabled(fetchingRate || isSaving)
        } footer: {
            VStack(alignment: .leading, spacing: 10) {
            if let saveError { Text(saveError).appFont(.body, weight: .regular).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("entryError") }
            HStack(spacing: MacUI.space(12)) {
                if existing == nil { Toggle(L10n.text("mac.transactionEditor.MacFormShell.3d9804711f"), isOn: $keepAdding).toggleStyle(.checkbox).appFont(.body, weight: .regular, design: .default).accessibilityIdentifier("entryKeepAdding") }
                Spacer(minLength: 8)
                Button(L10n.text("mac.transactionEditor.MacFormShell.2cd0f3be87")) { dismiss() }.buttonStyle(MacStandardButtonStyle()).accessibilityIdentifier("cancelEntry").keyboardShortcut(.cancelAction)
                Button(existing == nil ? L10n.text("mac.transactionEditor.MacFormShell.a3030bf8f1") : L10n.text("mac.transactionEditor.MacFormShell.991bb7cfe5")) { save() }.buttonStyle(MacStandardButtonStyle(primary: true))
                    .accessibilityIdentifier("saveEntry").keyboardShortcut(.defaultAction).disabled(isSaving || fetchingRate || !sameCurrencyEditable)
            }
        }
        }
            .environment(\.locale, localizationState.locale)
            .sheet(isPresented: $managingCategories, onDismiss: {
                if let id = managedCategoryID { category = categories.first { $0.id == id && $0.deletedAt == nil }?.name ?? "" }
            }) {
                VStack(spacing: MacUI.space(16)) {
                    HStack { Text(L10n.text("mac.transactionEditor.body.ee46fd8708")).appFont(.dialogTitle, weight: .semibold); Spacer(); Button(L10n.text("mac.transactionEditor.body.c0b3fbff51")) { managingCategories = false }.accessibilityIdentifier("entryCategoriesDone") }
                    ScrollView { MacCategoriesSettingsView(wide: MacUI.dialogWidth(720, available: MacUI.available.width) >= 700) }
                }.appPadding(20).appPanel(width: 720, height: 540).background(MacOverviewStyle.canvas)
            }
            .onAppear {
                categoryUsage = (try? MacCategoryUsageSnapshot.load(in: modelContext)) ?? .init()
                if let existing {
                    type = existing.typedType
                    amountText = MacTransactionCRUD.amountEditingText(existing.originalAmount)
                    category = existing.category; note = existing.note ?? ""; date = existing.date
                    originalCurrency = existing.originalCurrency; rateText = String(format: "%.6f", existing.exchangeRateToBase)
                    if existing.originalCurrency != bookCurrency {
                        // Saved monetary facts take precedence during an edit.
                        bankAmount = MacTransactionCRUD.amountEditingText(existing.baseAmount); useBankAmount = true
                    }
                } else { originalCurrency = bookCurrency }
                amountFocused = true
            }
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                categoryUsage = (try? MacCategoryUsageSnapshot.load(in: modelContext)) ?? .init()
            }
            .onChange(of: originalCurrency) { _, newValue in
                rateRequest = UUID(); fetchingRate = false
                let code = newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if code == bookCurrency { rateText = "1" }
                else if code != existing?.originalCurrency { rateText = ""; quoteMessage = nil; showsExchangeDetails = true }
            }
            .onChange(of: date) { _, newValue in
                rateRequest = UUID(); fetchingRate = false
                if foreignCurrency, newValue != existing?.date { rateText = ""; quoteMessage = nil }
            }
            .onChange(of: showsDatePicker) { _, isPresented in if !isPresented { entryDateFocused = true } }
    }

    private var entryDateLabel: String { MacEntryDateDisplay.string(date) }
    private var amountInput:some View {
        field(L10n.text("mac.transactionEditor.field.ffc624300d")) {
                            HStack(spacing: MacUI.space(3)) {
                                Text(type == .expense ? "−" : "+").foregroundStyle(.secondary)
                                MacNumericInput(text: $amountText, identifier: "entryAmount", focus: Binding(get: { amountFocused }, set: { amountFocused = $0 }), large: true).frame(minHeight: 36)
                                    .appFont(.amount, weight: .medium, design: .default).appMinHeight(36)
                                    .accessibilityLabel(L10n.text("mac.transactionEditor.field.ffc624300d")).accessibilityIdentifier("entryAmount")
                            }.appFont(.amount, weight: .medium, design: .default).appPadding(.horizontal, 14).appMinHeight(44)
                                .background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(amountFocused ? Color.blue : .gray.opacity(0.25), lineWidth: amountFocused ? 2 : 1))
                        }
    }
    private var currencyInput:some View {
        field(L10n.text("mac.transactionEditor.field.04ee13cd1d")) {MacEditableCurrencyMenu(currency:$originalCurrency,custom:$customCurrency,codes:currencyChoices,identifier:"entryCurrencyMenu",textIdentifier:"entryCurrency")}.frame(width:MacCurrencyMenuStyle.fieldWidth)
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        MacEntryField(title:title,content:content)
    }

    private func save() {
        guard !isSaving, sameCurrencyEditable else { return }
        isSaving = true
        defer { isSaving = false }
        let resolvedCategory = savedCategories.first { $0 == category || MacOverviewStyle.category($0) == category } ?? category
        let draft = MacTransactionCRUD.Draft(
            type: type, amountText: amountText,
            category: resolvedCategory, note: note, date: date
        )
        do {
            let source = try MacCurrency.code(originalCurrency)
            let rate = source == bookCurrency || useBankAmount ? 1 : try MacCurrency.rate(rateText)
            let actual = foreignCurrency && useBankAmount ? try MacTransactionCRUD.editedAmount(bankAmount, original: existing?.baseAmount ?? 0) : nil
            let id: UUID
            let savedRate: Double
            if let existing {
                try MacTransactionCRUD.update(
                    existing, with: draft, currency: bookCurrency,
                    originalCurrency: source, exchangeRate: rate, actualBaseAmount: actual, in: modelContext
                )
                id = existing.id; savedRate = existing.exchangeRateToBase
            } else {
                let created = try MacTransactionCRUD.create(
                    draft, currency: bookCurrency, originalCurrency: source,
                    exchangeRate: rate, actualBaseAmount: actual, in: modelContext
                )
                id = created.id; savedRate = created.exchangeRateToBase
            }
            onSaved?(id)
            if existing == nil && keepAdding {
                amountText = ""; note = ""; saveError = nil
                rateText = MacBankSettlement.reusableRateText(savedRate)
                useBankAmount = false; bankAmount = ""; quoteMessage = nil
                rateRequest = UUID(); fetchingRate = false
                savedMessage = L10n.text("mac.transactionEditor.save.6dc64f1412"); amountFocused = true
            } else { dismiss() }
        } catch {
            saveError = MacLocalization.error(error)
        }
    }

    private func fetchRate() {
        guard !fetchingRate else { return }
        fetchingRate = true
        saveError = nil
        let token = UUID(); rateRequest = token
        let requestedCurrency = originalCurrency, requestedDate = date
        Task { @MainActor in
            defer { if rateRequest == token { fetchingRate = false } }
            do {
                let source = try MacCurrency.code(requestedCurrency)
                let day = MacFXDates.tag(requestedDate, calendar: .current)
                let result = try await MacFXAccountingAdapter().accountingQuote(pair: MacFXPair(base: source, quote: bookCurrency), day: day)
                guard token == rateRequest, requestedCurrency == originalCurrency, requestedDate == date else { return }
                rateText = String(format: "%.6f", result.unitRate)
                quoteMessage = L10n.text("mac.transactionEditor.Task.2344fc5d1d") + day + " · " + MacFXApplication.shared.sourceLabel(result.identity.sourceID) + L10n.text("mac.transactionEditor.Task.219cf0f78c")
            } catch {
                guard token == rateRequest else { return }
                saveError = MacLocalization.error(error)
                quoteMessage = nil
            }
        }
    }
}
