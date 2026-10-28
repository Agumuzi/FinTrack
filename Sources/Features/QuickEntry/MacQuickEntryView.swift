import SwiftUI
import SwiftData

/// The main editor's form presentation, adapted to the 408-point menu host.
/// Its draft and financial write boundary remain app-owned.
struct MacQuickEntryView: View {
    @ObservedObject var draft: MacQuickEntryDraft
    @ObservedObject var runtime: MacApplicationRuntime
    @Environment(\.modelContext) private var context
    @AppStorage("base_currency",store:MacPreferences.defaults) private var preferred = "USD"
    @AppStorage("v2_category_styles",store:MacPreferences.defaults) private var styles = Data()
    @Query private var categories: [FinTrackMac.Category]
    @Query private var transactions: [Transaction]
    @Query private var deposits: [DepositRecord]
    @Query private var recurring: [RecurringTransaction]
    @Query private var loans: [LoanRule]
    @State private var datePicker = false
    @State private var categoryUsage = MacCategoryUsageSnapshot()
    @FocusState private var amountFocused: Bool
    @FocusState private var dateFocused: Bool
    private var base: String? {
        let resolution = MacCurrency.resolveLedgerCurrency(transactions:transactions,deposits:deposits,loans:loans,recurring:recurring,preferred:preferred)
        return resolution.matchesPreference ? resolution.displayCurrency : nil
    }
    private var validCategories: [FinTrackMac.Category] {
        categoryUsage.sorted(categories.filter { $0.deletedAt == nil && $0.type == draft.type.rawValue })
    }
    private var selected: FinTrackMac.Category? { validCategories.first { $0.id == draft.categoryID } }
    private var foreign: Bool { draft.currency.trimmingCharacters(in:.whitespacesAndNewlines).uppercased() != base }
    var body: some View {
        let _ = styles
        VStack(alignment:.leading,spacing:MacUI.space(16)) {
            MacEntryTypeSwitcher(type:Binding(get:{draft.type},set:{draft.income = $0 == .income}),prefix:"menu")
            ScrollView {
                VStack(alignment:.leading,spacing:MacUI.space(16)) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 14) { amountField.frame(minWidth:MacNumberInput.minimumEditingWidth()); currencyField }
                        VStack(alignment: .leading, spacing: 16) { amountField; currencyField }
                    }
                    MacEntryField(title: "分类") {
                        MacIconMenu(selection: Binding(get: { draft.categoryID?.uuidString ?? "" }, set: { draft.categoryID = UUID(uuidString: $0) }), options: [MacIconMenuOption(title: "请选择分类", value: "", symbol: "tag")] + validCategories.map { row in
                            MacIconMenuOption(title: MacOverviewStyle.category(row.name), value: row.id.uuidString, image: MacCategoryCatalog.menuImage(style: MacCategoryCatalog.style(name: row.name, type: draft.type.rawValue), name: row.name))
                        }, identifier: "menuCategory", accessibilityTitle: "选择分类", width: 340, fillsAvailableWidth: true).disabled(validCategories.isEmpty)
                    }
                    MacEntryField(title:"交易日期") {
                        Button { datePicker = true } label: {
                            HStack(spacing:MacUI.space(12)) {
                                Image(systemName:"calendar").appIconFont(22)
                                Text(MacEntryDateDisplay.string(draft.date)).appFont(.body,weight:.semibold)
                                Spacer(); Image(systemName:"chevron.down").appFont(.body,weight:.semibold)
                            }.appPadding(.horizontal,15).appMinHeight(40).modifier(MacEntryFieldBorder())
                        }.buttonStyle(MacInteractiveButtonStyle()).focused($dateFocused).accessibilityIdentifier("menuDate")
                            .accessibilityLabel("选择交易日期").accessibilityValue(MacEntryDateDisplay.string(draft.date))
                            .popover(isPresented:$datePicker) {
                                MacCalendarPickerPopover(title:"选择日期",selection:$draft.date,pickerIdentifier:"menuDatePicker",doneIdentifier:"menuDateDone",onDone:{datePicker = false})
                            }
                    }
                    MacEntryField(title:"备注（可选）") {
                        HStack(alignment:.top,spacing:MacUI.space(11)) {
                            Image(systemName:"doc.text").appIconFont(23).appPadding(.top,2)
                            TextField("添加备注，如：午餐、超市购物等…",text:$draft.note,axis:.vertical).textFieldStyle(.plain)
                                .lineLimit(2...3).appFont(.body,weight:.regular).accessibilityLabel("备注").accessibilityIdentifier("menuNote")
                            Text("\(draft.note.count) 字").appFont(.caption,weight:.regular).foregroundStyle(.secondary).monospacedDigit().appPadding(.top,3)
                        }.appPadding(14).frame(minHeight:58,alignment:.top).modifier(MacEntryFieldBorder())
                    }
                    if let base {
                        MacEntryExchangeCard(expanded:$draft.showsExchangeDetails,source:draft.currency,base:base,identifier:"menuExchangeDetails") {
                            Text("账本本位币：" + base).appFont(.body,weight:.regular).foregroundStyle(.secondary)
                            if foreign {
                                HStack(spacing:MacUI.space(10)) {
                                    Text("1 " + draft.currency.uppercased() + " =")
                                    TextField("输入汇率",text:Binding(get:{draft.displayedRate(base:base)},set:{draft.setManualRate($0, base:base)}))
                                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("menuRate")
                                    Text(base)
                                }.appFont(.body,weight:.regular)
                                Button(draft.fetching ? "获取中…" : "获取当日汇率") { Task { await draft.fetchRate(base:base) } }
                                    .disabled(draft.fetching).accessibilityIdentifier("menuFetchRate")
                                MacEntryField(title:"本币记账金额 · " + base) {
                                    TextField("自动计算，也可手动修改",text:Binding(get:{draft.amountText(base:base)},set:{draft.setManualBaseAmount($0, base:base)}))
                                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("menuBankAmount")
                                }
                                if draft.useBankAmount {
                                    Text("以手动金额为准，汇率按原币金额反推。").appFont(.caption,weight:.regular).foregroundStyle(.secondary)
                                    Button("按汇率重新计算") { draft.resetAmountToRate() }.accessibilityIdentifier("menuResetBankAmount")
                                } else { Text("按汇率自动计算，可直接修改本币金额。").appFont(.caption,weight:.regular).foregroundStyle(.secondary) }
                                if let message = draft.quoteMessage { Text(message).appFont(.caption,weight:.regular).foregroundStyle(.secondary) }
                            } else { Text("同币种无需换算。").appFont(.body,weight:.regular) }
                        }
                    } else { Text("账本包含多个本位币，请先在主窗口核对。").foregroundStyle(.red) }
                }.frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true).padding(2)
            }.scrollIndicators(.visible).accessibilityIdentifier("menuEntryFields")
            VStack(alignment:.leading,spacing:10) {
                if let error = draft.error { Text(error).appFont(.caption,weight:.regular).foregroundStyle(.red).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("menuEntryError") }
                if let message = draft.savedMessage { Text(message).appFont(.caption,weight:.regular).foregroundStyle(.green).accessibilityIdentifier("menuEntrySaved") }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { keepAdding; Spacer(minLength: 4); footerButtons }
                    VStack(alignment: .leading, spacing: 10) { keepAdding; HStack { Spacer(); footerButtons } }
                }

            }
        }.appFont(.body).buttonStyle(MacStandardButtonStyle()).tint(MacUI.accent)
        .task {
            categoryUsage = (try? MacCategoryUsageSnapshot.load(in: context)) ?? .init()
            if draft.currency.isEmpty { draft.currency = base ?? preferred }
            try? await Task.sleep(for:.milliseconds(50)); amountFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in categoryUsage = (try? MacCategoryUsageSnapshot.load(in: context)) ?? .init() }
        .onChange(of:draft.currency) { _, value in
            draft.invalidateQuote()
            if value.trimmingCharacters(in:.whitespacesAndNewlines).uppercased() != base { draft.showsExchangeDetails = true }
        }
        .onChange(of:draft.date) { _, _ in draft.invalidateQuote() }
        .onChange(of:base) { _, _ in draft.invalidateQuote(); draft.useBankAmount = false; draft.bankAmount = "" }
        .onChange(of:datePicker) { _, shown in if !shown { dateFocused = true } }
    }
    private var amountField: some View {
        MacEntryField(title: "金额") {
            HStack(spacing: 3) {
                Text(draft.income ? "+" : "−").foregroundStyle(.secondary)
                MacNumericInput(text: $draft.amount, identifier: "menuAmount", focus: Binding(get: { amountFocused }, set: { amountFocused = $0 }), submit: save, large: true)
                    .frame(minHeight: max(36,MacUI.fontSize(.amount,tier:MacUI.fontTier)+8)).accessibilityLabel("金额").accessibilityIdentifier("menuAmount")
            }.appFont(.amount, weight: .medium).padding(.horizontal,14).frame(minHeight:44)
                .background(MacOverviewStyle.card,in:RoundedRectangle(cornerRadius:9))
                .overlay(RoundedRectangle(cornerRadius:9).strokeBorder(amountFocused ? Color.blue : .gray.opacity(0.25),lineWidth:amountFocused ? 2 : 1))
        }
    }
    private var currencyField: some View {
        MacEntryField(title: "货币") {
            MacEditableCurrencyMenu(currency:$draft.currency,custom:$draft.customCurrencyEntry,codes:currencyChoices,identifier:"menuCurrency",textIdentifier:"menuCurrencyText")
        }.frame(width:MacCurrencyMenuStyle.fieldWidth)
    }
    private var keepAdding: some View {
        Toggle("保存后继续添加",isOn:$draft.continueAdding).toggleStyle(.checkbox).appFont(.body).accessibilityIdentifier("menuKeepAdding")
    }
    private var footerButtons: some View {
        HStack(spacing:12) {
            Button("取消") { runtime.closePanel() }.accessibilityIdentifier("menuCancelEntry").keyboardShortcut(.cancelAction)
            Button("保存") { save() }.buttonStyle(MacStandardButtonStyle(primary:true))
                .disabled(draft.isSaving || draft.fetching || base == nil).accessibilityIdentifier("menuSaveEntry").keyboardShortcut(.return,modifiers:.command)
        }.fixedSize()
    }
    private var currencyChoices: [String] { Array(Set(MacFXCatalog.codes + [base ?? preferred,draft.currency])).filter { !$0.isEmpty }.sorted() }
    private func save() {
        do {
            if try draft.save(context:context,preferredBase:preferred) != nil {
                if draft.continueAdding { amountFocused = true } else { runtime.closePanel() }
            }
        } catch { /* The app-owned draft retains the error and unsaved input. */ }
    }
}
