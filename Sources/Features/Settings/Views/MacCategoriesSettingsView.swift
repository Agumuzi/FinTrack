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
        guard !CategoryUsageHelper.isProtectedCategory(row) else { throw MacSettingsFailure.invalid("系统结息与贷款分类受保护") }
        guard try usage(row, in: context) == 0 else { throw MacSettingsFailure.invalid("此分类仍被账目、规则或预算引用，请先重命名或合并分类") }
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
        guard style.emoji == nil || MacCategoryEmoji.isValid(style.emoji!) else { throw MacSettingsFailure.invalid("请选择或输入一个 emoji") }
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
        VStack(alignment: .leading, spacing: MacUI.space(15)) {
            HStack(spacing: MacUI.space(0)) {
                categoryTab("支出分类", value: "Expense", icon: "arrow.down", color: .red)
                categoryTab("收入分类", value: "Income", icon: "arrow.up", color: .green)
            }.background(.gray.opacity(0.045), in: RoundedRectangle(cornerRadius: 9)).frame(maxWidth: MacUI.space(520))
            HStack { Text("排序").foregroundStyle(.secondary); MacSettingsMenu(selection: $sorting, options: ["手动顺序", "名称 A–Z", "名称 Z–A", "引用最多", "引用最少"].map { ($0, $0) }).frame(width: 180); Spacer() }
            MacSettingsColumns(wide: wide) {
                MacSettingsCard(title: type == "Expense" ? "支出分类" : "收入分类", icon: "tag", headerColor: .red, action: AnyView(Button("添加分类", systemImage: "plus") { select(nil) }.accessibilityIdentifier("settingsCategoryAdd")), compactHeader: true) {
                    HStack { Text("图标").frame(width: MacUI.space(40)); Text("名称"); Spacer(); Text("引用数量").frame(width: MacUI.space(70)); Text("操作").frame(width: MacUI.space(76)) }.appFont(.caption, weight: .medium, design: .default).foregroundStyle(.secondary).appPadding(9).background(.gray.opacity(0.04))
                    VStack(spacing: MacUI.space(0)) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            HStack(spacing: MacUI.space(9)) {
                                Button { select(row) } label: {
                                    HStack(spacing: MacUI.space(13)) {
                                        MacCategoryBadge(name: row.name, type: row.type, size: 34, suppliedStyle: MacCategoryCatalog.style(name: row.name, type: row.type, in: styles))
                                        Text(MacOverviewStyle.category(row.name)).appFont(.body, weight: .medium, design: .default)
                                        Spacer(minLength: 0)
                                        Text(usageSnapshot.map { String($0.count(for: row)) } ?? "—").appFont(.body, weight: .regular, design: .default).foregroundStyle(.secondary).frame(width: MacUI.space(55))
                                    }.contentShape(Rectangle())
                                }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier("settingsCategoryRow-" + row.name)
                                Image(systemName: "chevron.right").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                                Menu { Button("编辑") { select(row) }; Button("上移") { move(row, by: -1) }.disabled(index == 0); Button("下移") { move(row, by: 1) }.disabled(index == rows.count - 1) } label: { Image(systemName: "ellipsis").frame(width: MacUI.space(24)) }.menuStyle(.borderlessButton).fixedSize()
                                    .accessibilityLabel("分类操作：" + row.name).accessibilityIdentifier("settingsCategoryActions-" + row.name)
                            }.appPadding(.horizontal, 9).appMinHeight(51).background(selectedID == row.id ? MacSettingsVisual.accent.opacity(0.04) : .clear)
                            Divider()
                        }
                    }
                }
            } right: {
                VStack(spacing: MacUI.space(14)) {
                    MacSettingsCard(title: selected.map { MacOverviewStyle.category($0.name) } ?? "新建分类", icon: symbol, headerColor: MacAccent.color(color), action: AnyView(Button("删除分类", systemImage: "trash", role: .destructive) { remove = true }.disabled(selected == nil || selected.map(CategoryUsageHelper.isProtectedCategory) == true).accessibilityIdentifier("settingsCategoryDelete")), compactHeader: true) {
                        MacSettingsRow(label: "名称", labelWidth: 60) { TextField("分类名称", text: $name).accessibilityIdentifier("managedCategoryName") }
                        MacSymbolColorPicker(icon: $symbol, color: $color, title: "分类", identifierPrefix: "categoryIcon")
                        if let selected, CategoryUsageHelper.isProtectedCategory(selected) { Text("系统分类的显示名称和图标可以修改；内部结息/还款关联保持稳定。").appFont(.caption).foregroundStyle(.secondary) }
                        if let error { Text(error).appFont(.caption, weight: .regular).foregroundStyle(.red).accessibilityIdentifier("categorySettingsError") }
                        if let message { Text(message).appFont(.caption, weight: .regular).foregroundStyle(.green) }
                        HStack { Spacer(); Button("保存修改") { if let selected, name.trimmingCharacters(in: .whitespacesAndNewlines) != selected.name && name != MacOverviewStyle.category(selected.name) { rename = true } else { save() } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveManagedCategory") }
                    }
                    if let selected {
                        HStack { Label("历史引用", systemImage: "doc.text"); Spacer(); Text(usageSnapshot.map { "\($0.count(for: selected)) 次" } ?? "待核对") }.appFont(.caption).foregroundStyle(.secondary)
                    }
                    Text("重命名同步更新引用；使用中的分类不可删除。").appFont(.caption).foregroundStyle(.secondary)

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
        .confirmationDialog("放弃未保存修改？",isPresented:$discardDraft) {
            Button("放弃并重新载入",role:.destructive) {
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
        .alert("更新分类及全部引用？", isPresented: $rename) {
            Button("取消", role: .cancel) {}
            Button("重命名或合并") { save() }.accessibilityIdentifier("settingsCategoryRenameConfirm")
        } message: { Text("历史账目、周期规则和贷款会使用新名称；同名分类将合并，原有金额保持不变。") }
        .sheet(isPresented: $remove) {
            VStack(alignment: .leading, spacing: MacUI.space(18)) {
                Text("删除分类？").appFont(.dialogTitle, weight: .semibold)
                Text("只有未被账目、金融规则或预算引用的分类可以删除。")
                if extraCategoryConfirmation { Toggle("我已核对分类及历史引用", isOn: $categoryAcknowledged) }
                HStack {
                    Button("取消") { remove = false }
                    Spacer()
                    Button("删除", role: .destructive) {
                        guard let selected else { return }
                        do { try MacCategoryCatalog.remove(selected, in: context); select(nil); message = "分类已删除"; remove = false }
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
            message="有未保存修改；切页后可继续编辑"
        } else {
            name=row.map {MacOverviewStyle.category($0.name)} ?? ""
            let style=row.map {MacCategoryCatalog.style(name:$0.name,type:$0.type)} ?? MacCategoryStyle()
            symbol=style.symbol;color=style.color;loadedRevision=row?.updatedAt;message=nil
        }
        error=nil
    }
    private func save() {
        do {
            guard loadedRevision == selected?.updatedAt, draftGeneration == MacEditorDraftStore.shared.generation, selectedID == nil || selected != nil else { throw MacSettingsFailure.invalid("分类已变化，草稿仍保留。请重新选择分类并核对。") }
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
            MacEditorDraftStore.shared.remove(draftKey(selectedID,type:type));error = nil; message = "分类已保存"
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
