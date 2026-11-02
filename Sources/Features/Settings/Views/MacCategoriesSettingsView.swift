import SwiftUI
import SwiftData

@MainActor
enum MacCategoryCatalog {
    static let symbols = ["tag", "fork.knife", "cup.and.saucer", "birthday.cake", "takeoutbag.and.cup.and.straw", "cart", "bag", "house", "house.fill", "car", "car.fill", "heart", "heart.fill", "cross.case.fill", "book", "graduationcap.fill", "gift", "gift.fill", "airplane", "banknote", "banknote.fill", "chart.line.uptrend.xyaxis", "gamecontroller", "gamecontroller.fill", "palm.tree.fill", "suitcase.fill", "ellipsis", "tshirt.fill", "dollarsign.circle"]
    static var colors: [String] { MacPresentationOptions.palette }
    private static var menuCache: [String: NSImage] = [:]
    static func menuImage(style: MacCategoryStyle, name: String) -> NSImage {
        let key = style.symbol + ":" + style.color
        if let image = menuCache[key] { return image }
        let image = NSImage(size: NSSize(width: 22, height: 22))
        image.lockFocus()
        if let symbol = NSImage(systemSymbolName: style.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 17, weight: .medium))?.withSymbolConfiguration(.init(paletteColors: [NSColor(MacAccent.color(style.color))])) { symbol.draw(in: NSRect(x: 1, y: 1, width: 20, height: 20)) }
        image.unlockFocus(); image.isTemplate = false; image.setName(NSImage.Name(key))
        if menuCache.count > 256 { menuCache.removeAll() }; menuCache[key] = image; return image
    }
    static func key(name: String, type: String) -> String { type + ":" + name }
    static func style(name: String, type: String) -> MacCategoryStyle {
        let all: [String: MacCategoryStyle] = MacSettingsStore.load("v2_category_styles", fallback: [:])
        return style(name: name, type: type, in: all)
    }
    static func style(name: String, type: String, in all: [String: MacCategoryStyle]) -> MacCategoryStyle {
        var value = all[key(name: name, type: type)] ?? MacCategoryStyle(symbol: defaultSymbol(name), color: type == "Income" ? "green" : "orange")
        // v1.3 intentionally resets legacy emoji to the category default icon.
        // Old bytes remain readable; choosing a new icon saves emoji == nil.
        if value.emoji != nil { value.symbol = defaultSymbol(name); value.emoji = nil }
        return value
    }
    static func emoji(name: String, type: String = "Expense") -> String {
        let value = style(name: name, type: type)
        return emoji(style: value, name: name)
    }
    static func emoji(style value: MacCategoryStyle, name: String) -> String {
        value.emoji.flatMap { MacCategoryEmoji.isValid($0) ? $0 : nil } ?? MacCategoryEmoji.fallback(symbol: value.symbol, name: name)
    }
    static func defaultSymbol(_ name: String) -> String {
        switch name { case "Dining", "餐饮": "fork.knife"; case "Shopping", "购物": "cart"; case "Housing", "住房": "house"; case "Salary", "工资": "banknote"; case "交通": "car"; default: "tag" }
    }
    static func usage(_ row: Category, in context: ModelContext) throws -> Int {
        try MacCategoryUsageSnapshot.load(in: context).count(for: row)
    }
    static func remove(_ row: Category, in context: ModelContext) throws {
        guard !CategoryUsageHelper.isProtectedCategory(row) else { throw MacSettingsFailure.invalid(L10n.text("mac.categoriesSettingsView.remove.2ddd6f38b5")) }
        guard try usage(row, in: context) == 0 else { throw MacSettingsFailure.invalid(L10n.text("mac.categoriesSettingsView.remove.0f589de0c1")) }
        context.delete(row)
        do { try context.save() } catch { context.rollback(); throw error }
    }
    static func reorder(_ rows: [Category], type: String) throws {
        var all: [String: MacCategoryStyle] = MacSettingsStore.load("v2_category_styles", fallback: [:])
        for (index, row) in rows.enumerated() {
            var value = style(name: row.name, type: type, in: all)
            value.order = index
            all[key(name: row.name, type: type)] = value
        }
        try MacSettingsStore.save(all, key: "v2_category_styles")
    }
    static func saveStyle(_ style: MacCategoryStyle, name: String, type: String) throws {
        guard style.emoji == nil || MacCategoryEmoji.isValid(style.emoji!) else { throw MacSettingsFailure.invalid(L10n.text("mac.categoriesSettingsView.saveStyle.a8111bad5d")) }
        var all: [String: MacCategoryStyle] = MacSettingsStore.load("v2_category_styles", fallback: [:])
        all[key(name: name, type: type)] = style
        try MacSettingsStore.save(all, key: "v2_category_styles")
    }
}

struct MacCategoryBadge: View {
    var name: String
    var type = "Expense"
    var size: CGFloat = 32
    var filled = true
    var suppliedStyle: MacCategoryStyle? = nil
    @AppStorage("v2_category_styles") private var revision = Data()
    var body: some View {
        let _ = revision
        let style = suppliedStyle ?? MacCategoryCatalog.style(name: name, type: type)
        Image(systemName: style.symbol).appIconFont(size * 0.53).foregroundStyle(MacAccent.color(style.color)).frame(width: MacUI.space(size), height: MacUI.space(size))
            .background(MacAccent.color(style.color).opacity(filled ? 0.14 : 0.1), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}

struct MacCategoriesSettingsView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    @AppStorage(MacCustomTypography.bodyKey,store:MacPreferences.defaults) private var bodyPoints=16
    @AppStorage(MacCustomTypography.captionKey,store:MacPreferences.defaults) private var captionPoints=12
    @AppStorage(MacInterfaceFonts.preferenceKey,store:MacPreferences.defaults) private var interfaceFont=""

    var wide: Bool
    @Environment(\.modelContext) private var context
    @Query private var categories: [Category]
    @AppStorage("v2_category_styles") private var revision = Data()
    @State private var usageSnapshot: MacCategoryUsageSnapshot?
    @State private var styles: [String: MacCategoryStyle] = [:]
    @State private var usageRevision = 0
    @AppStorage("v2_budgets") private var budgetRevision = Data()
    @State private var type = "Expense"
    @State private var sorting = "引用最多"
    @State private var selectedID: UUID?
    @State private var name = ""
    private struct Draft { let name: String; let symbol: String; let color: String; let revision: Date?; let generation: Int }
    @State private var discardDraft = false
    @State private var loadedRevision: Date?
    @State private var draftGeneration = 0
    @State private var activeType = "Expense"
    private func draftKey(_ id: UUID?, type: String) -> String { MacEditorDraftStore.key("category-"+type,id?.uuidString ?? "new",context:context) }
    private func keepDraft() {
        let originalName=selected.map {MacOverviewStyle.category($0.name)} ?? ""
        let originalStyle=selected.map {MacCategoryCatalog.style(name:$0.name,type:$0.type)} ?? MacCategoryStyle()
        if name != originalName || symbol != originalStyle.symbol || color != originalStyle.color {
            MacEditorDraftStore.shared.save(Draft(name:name,symbol:symbol,color:color,revision:loadedRevision,generation:draftGeneration),key:draftKey(selectedID,type:activeType),generation:draftGeneration)
        } else {MacEditorDraftStore.shared.remove(draftKey(selectedID,type:activeType))}
        MacEditorDraftStore.shared.save(selectedID?.uuidString ?? "new",key:MacEditorDraftStore.key("category-selection",activeType,context:context),generation:draftGeneration)
    }

    @State private var symbol = "tag"
    @State private var color = "orange"
    @State private var message: String?
    @State private var error: String?
    @AppStorage("v2_confirm_categories") private var extraCategoryConfirmation = true
    @State private var categoryAcknowledged = false
    @State private var rename = false
    @State private var remove = false
    private var selected: Category? { categories.first { $0.id == selectedID && $0.deletedAt == nil } }
    private var rows: [Category] {
        let _ = revision
        return categories.filter { $0.deletedAt == nil && $0.type == type }.sorted {
            if sorting == "名称 A–Z" { return MacOverviewStyle.category($0.name).localizedStandardCompare(MacOverviewStyle.category($1.name)) == .orderedAscending }
            if sorting == "名称 Z–A" { return MacOverviewStyle.category($0.name).localizedStandardCompare(MacOverviewStyle.category($1.name)) == .orderedDescending }
            if sorting == "引用最多", let usageSnapshot { let a = usageSnapshot.count(for: $0), b = usageSnapshot.count(for: $1); if a != b { return a > b } }
            if sorting == "引用最少", let usageSnapshot { let a = usageSnapshot.count(for: $0), b = usageSnapshot.count(for: $1); if a != b { return a < b } }
            let a = MacCategoryCatalog.style(name: $0.name, type: type, in: styles).order, b = MacCategoryCatalog.style(name: $1.name, type: type, in: styles).order
            return a == b ? $0.createdAt < $1.createdAt : a < b
        }
    }
    var body: some View {
        let rows = self.rows
        let _=bodyPoints;let _=captionPoints;let _=interfaceFont
        let captionFont=MacInterfaceFonts.font(size:MacUI.fontTier.captionSize)
        let countFont=MacInterfaceFonts.font(size:MacUI.fontTier.bodySize,monospacedDigits:true)
        let iconWidth=max(40,ceil((L10n.text("mac.categoriesSettingsView.ceil.0d720eeea2") as NSString).size(withAttributes:[.font:captionFont]).width)+12)
        let largestCount=rows.map {row in ((usageSnapshot.map{String($0.count(for:row))} ?? "—") as NSString).size(withAttributes:[.font:countFont]).width}.max() ?? 0
        let referenceWidth=max(70,max(ceil((L10n.text("mac.categoriesSettingsView.ceil.e0ec651f0d") as NSString).size(withAttributes:[.font:captionFont]).width)+12,ceil(largestCount)+12))
        let actionWidth=max(76,ceil((L10n.text("mac.categoriesSettingsView.ceil.ed31fbb483") as NSString).size(withAttributes:[.font:captionFont]).width)+12)
        VStack(alignment: .leading, spacing: MacUI.space(15)) {
            HStack(spacing: MacUI.space(0)) {
                categoryTab(L10n.text("mac.categoriesSettingsView.categoryTab.b6a1a504a8"), value: "Expense", icon: "arrow.down", color: .red)
                categoryTab(L10n.text("mac.categoriesSettingsView.categoryTab.ba01282192"), value: "Income", icon: "arrow.up", color: .green)
            }.background(.gray.opacity(0.045), in: RoundedRectangle(cornerRadius: 9)).frame(maxWidth: MacUI.space(520))
            HStack { Text(L10n.text("mac.categoriesSettingsView.body.a96c9a8541")).foregroundStyle(.secondary); MacSettingsMenu(selection: $sorting, options: ["手动顺序", "名称 A–Z", "名称 Z–A", "引用最多", "引用最少"].map { (L10n.builtIn($0), $0) }).frame(width: 180); Spacer() }
            MacSettingsColumns(wide: wide) {
                MacSettingsCard(title: type == "Expense" ? L10n.text("mac.categoriesSettingsView.MacSettingsColumns.b6a1a504a8") : L10n.text("mac.categoriesSettingsView.MacSettingsColumns.ba01282192"), icon: "tag", headerColor: .red, action: AnyView(Button(L10n.text("mac.categoriesSettingsView.AnyView.c6f37061bf"), systemImage: "plus") { select(nil) }.accessibilityIdentifier("settingsCategoryAdd")), compactHeader: true) {
                    HStack(spacing:13) {Text(L10n.text("mac.categoriesSettingsView.MacSettingsColumns.0d720eeea2")).fixedSize().frame(width:iconWidth);Text(L10n.text("mac.categoriesSettingsView.MacSettingsColumns.d44e9b3d3b")).frame(maxWidth:.infinity,alignment:.leading);Text(L10n.text("mac.categoriesSettingsView.MacSettingsColumns.e0ec651f0d")).accessibilityLabel(L10n.text("mac.categoriesSettingsView.MacSettingsColumns.2cb3b77f75")).fixedSize().frame(width:referenceWidth,alignment:.trailing);Text(L10n.text("mac.categoriesSettingsView.MacSettingsColumns.ed31fbb483")).fixedSize().frame(width:actionWidth)}.appFont(.caption, weight: .medium, design: .default).foregroundStyle(.secondary).appPadding(9).background(.gray.opacity(0.04))
                    VStack(spacing: MacUI.space(0)) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            HStack(spacing:13) {
                                Button { select(row) } label: {
                                    HStack(spacing:13) {
                                        MacCategoryBadge(name: row.name, type: row.type, size: 34, suppliedStyle: MacCategoryCatalog.style(name: row.name, type: row.type, in: styles)).frame(width:iconWidth)
                                        Text(MacOverviewStyle.category(row.name)).appFont(.body, weight: .medium, design: .default).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
                                        Text(usageSnapshot.map { String($0.count(for: row)) } ?? "—").appFont(.body, weight: .regular, design: .default).foregroundStyle(.secondary).monospacedDigit().fixedSize().frame(width:referenceWidth,alignment:.trailing)
                                    }.contentShape(Rectangle())
                                }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("settingsCategoryRow-" + row.name)
                                HStack(spacing:9) {
                                Image(systemName: "chevron.right").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                                Menu { Button(L10n.text("mac.categoriesSettingsView.Menu.0518365699")) { select(row) }; Button(L10n.text("mac.categoriesSettingsView.Menu.f853a70b12")) { move(row, by: -1) }.disabled(index == 0); Button(L10n.text("mac.categoriesSettingsView.Menu.e75e8b4e5c")) { move(row, by: 1) }.disabled(index == rows.count - 1) } label: { Text(L10n.text("mac.categoriesSettingsView.MacSettingsColumns.ed31fbb483")).appFont(.caption).lineLimit(1) }.menuStyle(.borderlessButton).fixedSize()
                                    .accessibilityLabel(L10n.text("mac.categoriesSettingsView.ForEach.896643fe85") + row.name).accessibilityIdentifier("settingsCategoryActions-" + row.name)
                                }.frame(width:actionWidth,alignment:.trailing)
                            }.appPadding(.horizontal, 9).appMinHeight(51).background(selectedID == row.id ? MacSettingsVisual.accent.opacity(0.04) : .clear)
                            Divider()
                        }
                    }
                }
            } right: {
                VStack(spacing: MacUI.space(14)) {
                    MacSettingsCard(title: selected.map { MacOverviewStyle.category($0.name) } ?? L10n.text("mac.categoriesSettingsView.MacSettingsColumns.197d990056"), icon: symbol, headerColor: MacAccent.color(color), action: AnyView(Button(L10n.text("mac.categoriesSettingsView.AnyView.e6bd4829e1"), systemImage: "trash", role: .destructive) { remove = true }.disabled(selected == nil || selected.map(CategoryUsageHelper.isProtectedCategory) == true).accessibilityIdentifier("settingsCategoryDelete")), compactHeader: true) {
                        MacSettingsRow(label: L10n.text("mac.categoriesSettingsView.MacSettingsColumns.d44e9b3d3b"), labelWidth: 60) { TextField(L10n.text("mac.categoriesSettingsView.MacSettingsColumns.9f304633b3"), text: $name).accessibilityIdentifier("managedCategoryName") }
                        MacSymbolColorPicker(icon: $symbol, color: $color, title: L10n.text("mac.categoriesSettingsView.MacSymbolColorPicker.515559957f"), identifierPrefix: "categoryIcon")
                        if let selected, CategoryUsageHelper.isProtectedCategory(selected) { Text(L10n.text("mac.categoriesSettingsView.MacSettingsColumns.9e8ecfa4a5")).appFont(.caption).foregroundStyle(.secondary) }
                        if let error { Text(error).appFont(.caption, weight: .regular).foregroundStyle(.red).accessibilityIdentifier("categorySettingsError") }
                        if let message { Text(message).appFont(.caption, weight: .regular).foregroundStyle(.green) }
                        HStack { Spacer(); Button(L10n.text("mac.categoriesSettingsView.MacSettingsColumns.991bb7cfe5")) { if let selected, name.trimmingCharacters(in: .whitespacesAndNewlines) != selected.name && name != MacOverviewStyle.category(selected.name) { rename = true } else { save() } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveManagedCategory") }
                    }
                    if let selected {
                        HStack { Label(L10n.text("mac.categoriesSettingsView.MacSettingsColumns.11e5f33386"), systemImage: "doc.text"); Spacer(); Text(usageSnapshot.map { L10n.format("mac.categoriesSettingsView.MacSettingsColumns.7ce874913e", "\($0.count(for: selected))") } ?? L10n.text("mac.categoriesSettingsView.MacSettingsColumns.33df16b4af")) }.appFont(.caption).foregroundStyle(.secondary)
                    }
                    Text(L10n.text("mac.categoriesSettingsView.MacSettingsColumns.0761748a71")).appFont(.caption).foregroundStyle(.secondary)

                }
            }
        }
        .onAppear {
            refreshStyles()
            let value=MacEditorDraftStore.shared.load(MacEditorDraftStore.key("category-selection",type,context:context),as:String.self)
            let id=value.flatMap(UUID.init(uuidString:))
            select(value == "new" ? nil : rows.first(where:{$0.id == id}) ?? rows.first, retainingCurrent:false)
        }
        .onDisappear { keepDraft() }
        .confirmationDialog(L10n.text("mac.categoriesSettingsView.body.46c8da8a29"),isPresented:$discardDraft) {
            Button(L10n.text("mac.categoriesSettingsView.body.ab0eba1876"),role:.destructive) {
                MacEditorDraftStore.shared.remove(draftKey(selectedID,type:activeType))
                select(selected ?? rows.first,retainingCurrent:false)
            }
        }
        .task(id: usageRevision) { refreshUsage() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { notification in
            if let saved = notification.object as? ModelContext, saved.container !== context.container { return }
            usageRevision &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: MacSettingsStore.restoreCompleted)) { _ in
            refreshStyles(); usageRevision &+= 1
        }
        .onChange(of: budgetRevision) { usageRevision &+= 1 }
        .onChange(of: revision) { refreshStyles() }
        .onChange(of: type) { select(rows.first) }
        .alert(L10n.text("mac.categoriesSettingsView.body.f623346d16"), isPresented: $rename) {
            Button(L10n.text("mac.categoriesSettingsView.body.2cd0f3be87"), role: .cancel) {}
            Button(L10n.text("mac.categoriesSettingsView.body.88aea11c2d")) { save() }.accessibilityIdentifier("settingsCategoryRenameConfirm")
        } message: { Text(L10n.text("mac.categoriesSettingsView.body.f02a91385e")) }
        .sheet(isPresented: $remove) {
            VStack(alignment: .leading, spacing: MacUI.space(18)) {
                Text(L10n.text("mac.categoriesSettingsView.body.0e1df5a6c9")).appFont(.dialogTitle, weight: .semibold)
                Text(L10n.text("mac.categoriesSettingsView.body.941b16a55e"))
                if extraCategoryConfirmation { Toggle(L10n.text("mac.categoriesSettingsView.body.43b93fcc1a"), isOn: $categoryAcknowledged) }
                HStack {
                    Button(L10n.text("mac.categoriesSettingsView.body.2cd0f3be87")) { remove = false }
                    Spacer()
                    Button(L10n.text("mac.categoriesSettingsView.body.2f9daa8289"), role: .destructive) {
                        guard let selected else { return }
                        do { try MacCategoryCatalog.remove(selected, in: context); select(nil); message = L10n.text("mac.categoriesSettingsView.body.3bc9b99371"); remove = false }
                        catch { self.error = MacLocalization.error(error); remove = false }
                    }.disabled(extraCategoryConfirmation && !categoryAcknowledged).accessibilityIdentifier("settingsCategoryDeleteConfirm")
                }
            }.appPadding(26).appDialog(width: 440).onAppear { categoryAcknowledged = false }
        }
    }
    private func categoryTab(_ title: String, value: String, icon: String, color: Color) -> some View {
        Button { type = value } label: { Label(title, systemImage: icon).appFont(.body, weight: .semibold, design: .default).frame(maxWidth: .infinity).appMinHeight(42).contentShape(Rectangle()).foregroundStyle(type == value ? color : .primary).background(type == value ? color.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(MacInteractiveButtonStyle())
    }
    private func select(_ row: Category?, retainingCurrent: Bool = true) {
        if retainingCurrent { keepDraft() }
        selectedID=row?.id;activeType=type;draftGeneration=MacEditorDraftStore.shared.generation
        if let d=MacEditorDraftStore.shared.load(draftKey(row?.id,type:type),as:Draft.self) {
            name=d.name;symbol=d.symbol;color=d.color;loadedRevision=d.revision;draftGeneration=d.generation
            message=L10n.text("mac.categoriesSettingsView.select.58937dd581")
        } else {
            name=row.map {MacOverviewStyle.category($0.name)} ?? ""
            let style=row.map {MacCategoryCatalog.style(name:$0.name,type:$0.type)} ?? MacCategoryStyle()
            symbol=style.symbol;color=style.color;loadedRevision=row?.updatedAt;message=nil
        }
        error=nil
    }
    private func save() {
        do {
            guard loadedRevision == selected?.updatedAt, draftGeneration == MacEditorDraftStore.shared.generation, selectedID == nil || selected != nil else { throw MacSettingsFailure.invalid(L10n.text("mac.categoriesSettingsView.save.a90c8b48e9")) }
            try MacRecoveryJournal.perform(in: context) {
            var clean = try MacTransactionCRUD.validatedCategory(name)
            var order = selected.map { MacCategoryCatalog.style(name: $0.name, type: type).order } ?? ((rows.map { MacCategoryCatalog.style(name: $0.name, type: type).order }.max() ?? -1) + 1)
            if let selected {
                let oldID = selected.id, oldName = selected.name
                if clean != oldName && clean != MacOverviewStyle.category(oldName) {
                    let target = categories.first { $0.deletedAt == nil && $0.type == type && $0.id != oldID && $0.name.localizedCaseInsensitiveCompare(clean) == .orderedSame }
                    if let target { order = MacCategoryCatalog.style(name: target.name, type: type).order }
                    try MacDataManagement.rename(selected, to: clean, in: context)
                    selectedID = target?.id ?? oldID
                    clean = target?.name ?? selected.name
                    if CategoryUsageHelper.isProtectedCategory(selected) { clean = oldName }
                } else { clean = oldName }
            } else {
                let row = CategoryUsageHelper.ensureCategoryExists(name: clean, type: type, in: context, existingCategories: categories)
                try context.save(); selectedID = row?.id; clean = row?.name ?? clean
            }
            let alias = selected.map { MacCategoryCatalog.style(name: $0.name, type: type).displayName } ?? nil
            try MacCategoryCatalog.saveStyle(.init(symbol: symbol, color: color, order: order, emoji: nil, displayName: alias), name: clean, type: type)
            // Coalesce save and budget notifications into the task below.
            // A style-only save does not change references.
            refreshStyles()
            name = MacOverviewStyle.category(clean);loadedRevision=try context.fetch(FetchDescriptor<Category>()).first(where:{$0.id == selectedID})?.updatedAt
            MacEditorDraftStore.shared.remove(draftKey(selectedID,type:type));error = nil; message = L10n.text("mac.categoriesSettingsView.save.9f4c4eb182")
            }
        } catch { context.rollback(); self.error = MacLocalization.error(error) }
    }
    private func refreshStyles() {
        styles = MacSettingsStore.load("v2_category_styles", fallback: [:])
    }
    private func refreshUsage() {
        do { usageSnapshot = try MacCategoryUsageSnapshot.load(in: context) }
        catch { usageSnapshot = nil; self.error = MacLocalization.error(error) }
    }
    private func move(_ row: Category, by offset: Int) {
        var list = rows; guard let index = list.firstIndex(where: { $0.id == row.id }), list.indices.contains(index + offset) else { return }
        list.swapAt(index, index + offset)
        do { try MacCategoryCatalog.reorder(list, type: type); refreshStyles() }
        catch { self.error = MacLocalization.error(error) }
    }
}
