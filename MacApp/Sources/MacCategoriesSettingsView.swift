import SwiftUI
import SwiftData

@MainActor
enum MacCategoryCatalog {
    static let symbols = ["tag", "fork.knife", "cup.and.saucer", "birthday.cake", "takeoutbag.and.cup.and.straw", "cart", "bag", "house", "house.fill", "car", "car.fill", "heart", "heart.fill", "cross.case.fill", "book", "graduationcap.fill", "gift", "gift.fill", "airplane", "banknote", "banknote.fill", "chart.line.uptrend.xyaxis", "gamecontroller", "gamecontroller.fill", "palm.tree.fill", "suitcase.fill", "ellipsis", "tshirt.fill", "dollarsign.circle"]
    static let colors = ["red", "orange", "yellow", "blue", "green", "purple", "pink", "terracotta"]
    static func key(name: String, type: String) -> String { type + ":" + name }
    static func style(name: String, type: String) -> MacCategoryStyle {
        let all: [String: MacCategoryStyle] = MacSettingsStore.load("v2_category_styles", fallback: [:])
        return all[key(name: name, type: type)] ?? MacCategoryStyle(symbol: defaultSymbol(name), color: type == "Income" ? "green" : "orange")
    }
    static func emoji(name: String, type: String = "Expense") -> String {
        let value = style(name: name, type: type)
        return value.emoji.flatMap { MacCategoryEmoji.isValid($0) ? $0 : nil } ?? MacCategoryEmoji.fallback(symbol: value.symbol, name: name)
    }
    static func defaultSymbol(_ name: String) -> String {
        switch name { case "Dining", "餐饮": "fork.knife"; case "Shopping", "购物": "cart"; case "Housing", "住房": "house"; case "Salary", "工资": "banknote"; case "交通": "car"; default: "tag" }
    }
    static func usage(_ row: Category, in context: ModelContext) throws -> Int {
        let transactions = try context.fetch(FetchDescriptor<Transaction>()).filter { $0.type == row.type && $0.category == row.name }.count
        let rules = try context.fetch(FetchDescriptor<RecurringTransaction>()).filter { $0.typedType.storageValue == row.type && $0.category == row.name }.count
        let loans = row.type == "Expense" ? try context.fetch(FetchDescriptor<LoanRule>()).filter { $0.category == row.name }.count : 0
        let budgets: [MacBudget] = MacSettingsStore.load("v2_budgets", fallback: [])
        return transactions + rules + loans + budgets.filter { $0.categoryID == row.id || ($0.categoryID == nil && $0.categoryName == row.name && row.type == "Expense") }.count
    }
    static func remove(_ row: Category, in context: ModelContext) throws {
        guard !CategoryUsageHelper.isProtectedCategory(row) else { throw MacSettingsFailure.invalid("系统结息与贷款分类受保护") }
        guard try usage(row, in: context) == 0 else { throw MacSettingsFailure.invalid("此分类仍被账目、规则或预算引用，请先重命名或合并分类") }
        context.delete(row)
        do { try context.save() } catch { context.rollback(); throw error }
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
    @AppStorage("v2_category_styles") private var revision = Data()
    var body: some View {
        let _ = revision
        let style = MacCategoryCatalog.style(name: name, type: type)
        Text(MacCategoryCatalog.emoji(name: name, type: type)).appIconFont(size * 0.6, weight: .regular, design: .default).frame(width: MacUI.space(size), height: MacUI.space(size))
            .foregroundStyle(.primary).background(MacAccent.color(style.color).opacity(filled ? 0.14 : 0.1), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}

struct MacCategoriesSettingsView: View {
    var wide: Bool
    @Environment(\.modelContext) private var context
    @Query private var categories: [Category]
    @AppStorage("v2_category_styles") private var revision = Data()
    @State private var type = "Expense"
    @State private var selectedID: UUID?
    @State private var name = ""
    @State private var symbol = "tag"
    @State private var emoji = "🏷️"
    @State private var color = "orange"
    @State private var message: String?
    @State private var error: String?
    @AppStorage("v2_confirm_categories") private var extraCategoryConfirmation = true
    @State private var categoryAcknowledged = false
    @State private var moreIcons = false
    @State private var rename = false
    @State private var remove = false
    private var selected: Category? { categories.first { $0.id == selectedID && $0.deletedAt == nil } }
    private var rows: [Category] {
        let _ = revision
        return categories.filter { $0.deletedAt == nil && $0.type == type }.sorted {
            let a = MacCategoryCatalog.style(name: $0.name, type: type).order, b = MacCategoryCatalog.style(name: $1.name, type: type).order
            return a == b ? $0.createdAt < $1.createdAt : a < b
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(15)) {
            HStack(spacing: MacUI.space(0)) {
                categoryTab("支出分类", value: "Expense", icon: "arrow.down", color: .red)
                categoryTab("收入分类", value: "Income", icon: "arrow.up", color: .green)
            }.background(.gray.opacity(0.045), in: RoundedRectangle(cornerRadius: 9)).frame(maxWidth: MacUI.space(520))
            MacSettingsColumns(wide: wide) {
                MacSettingsCard(title: type == "Expense" ? "支出分类" : "收入分类", icon: "tag", headerColor: .red, action: AnyView(Button("添加分类", systemImage: "plus") { select(nil) }.accessibilityIdentifier("settingsCategoryAdd")), compactHeader: true) {
                    HStack { Text("图标").frame(width: MacUI.space(40)); Text("名称"); Spacer(); Text("引用数量").frame(width: MacUI.space(70)); Text("操作").frame(width: MacUI.space(76)) }.appFont(.caption, weight: .medium, design: .default).foregroundStyle(.secondary).appPadding(9).background(.gray.opacity(0.04))
                    VStack(spacing: MacUI.space(0)) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            HStack(spacing: MacUI.space(9)) {
                                Button { select(row) } label: {
                                    HStack(spacing: MacUI.space(13)) {
                                        MacCategoryBadge(name: row.name, type: row.type, size: 34)
                                        Text(MacOverviewStyle.category(row.name)).appFont(.body, weight: .medium, design: .default)
                                        Spacer(minLength: 0)
                                        Text((try? MacCategoryCatalog.usage(row, in: context)).map { String($0) } ?? "—").appFont(.body, weight: .regular, design: .default).foregroundStyle(.secondary).frame(width: MacUI.space(55))
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityIdentifier("settingsCategoryRow-" + row.name)
                                Image(systemName: "chevron.right").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                                Menu { Button("编辑") { select(row) }; Button("上移") { move(row, by: -1) }.disabled(index == 0); Button("下移") { move(row, by: 1) }.disabled(index == rows.count - 1) } label: { Image(systemName: "ellipsis").frame(width: MacUI.space(24)) }.menuStyle(.borderlessButton).fixedSize()
                            }.appPadding(.horizontal, 9).appMinHeight(51).background(selectedID == row.id ? MacSettingsVisual.accent.opacity(0.04) : .clear)
                            Divider()
                        }
                    }
                }
            } right: {
                VStack(spacing: MacUI.space(14)) {
                    MacSettingsCard(title: selected.map { MacOverviewStyle.category($0.name) } ?? "新建分类", icon: emoji, headerColor: MacAccent.color(color), action: AnyView(Button("删除分类", systemImage: "trash", role: .destructive) { remove = true }.disabled(selected == nil || selected.map(CategoryUsageHelper.isProtectedCategory) == true).accessibilityIdentifier("settingsCategoryDelete")), compactHeader: true) {
                        MacSettingsRow(label: "名称", labelWidth: 60) { TextField("分类名称", text: $name).accessibilityIdentifier("managedCategoryName") }
                        MacSettingsRow(label: "图标", labelWidth: 60) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: MacUI.space(38)))], spacing: MacUI.space(8)) {
                                ForEach(Array(MacCategoryEmoji.choices.prefix(6)), id: \.self) { icon in iconChoice(icon) }
                                Button { moreIcons = true } label: { Image(systemName: "ellipsis").frame(width: MacUI.space(31), height: MacUI.space(31)).background(.gray.opacity(0.045), in: Circle()) }.buttonStyle(.plain).help("更多 emoji").accessibilityIdentifier("categoryMoreEmoji")
                            }
                        }
                        MacSettingsRow(label: "颜色", labelWidth: 60) { MacColorChoices(selection: $color) }
                        if let selected, CategoryUsageHelper.isProtectedCategory(selected) { Text("系统结息和贷款分类受保护，名称不可更改。").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary) }
                        if let error { Text(error).appFont(.caption, weight: .regular).foregroundStyle(.red).accessibilityIdentifier("categorySettingsError") }
                        if let message { Text(message).appFont(.caption, weight: .regular).foregroundStyle(.green) }
                        HStack { Spacer(); Button("保存修改") { if let selected, name.trimmingCharacters(in: .whitespacesAndNewlines) != selected.name && name != MacOverviewStyle.category(selected.name) { rename = true } else { save() } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveManagedCategory") }
                    }
                    MacSettingsCard(title: "分类使用", icon: "doc.text", subtitle: "本分类用于记账、周期规则与预算。", headerColor: .gray) {
                        if let selected { LabeledContent("历史引用", value: (try? MacCategoryCatalog.usage(selected, in: context)).map { "\($0) 次" } ?? "待核对") }
                        Text("重命名会同步更新已有引用；被使用的分类不可直接删除。").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .sheet(isPresented: $moreIcons) {
            VStack(alignment: .leading, spacing: MacUI.space(20)) {
                Text("选择分类 emoji").appFont(.dialogTitle, weight: .semibold)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(48)), count: 7), spacing: MacUI.space(14)) { ForEach(MacCategoryEmoji.choices, id: \.self) { icon in iconChoice(icon) } }
                HStack { Text("自定义 emoji"); TextField("输入一个 emoji", text: $emoji).accessibilityIdentifier("categoryCustomEmoji"); Button("完成") { moreIcons = false }.disabled(!MacCategoryEmoji.isValid(emoji)) }
            }.appPadding(26)
        }
        .onAppear { if rows.isEmpty { do { try MacDataManagement.seedCategories(in: context) } catch { self.error = MacLocalization.error(error) } }; select(rows.first) }
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
        Button { type = value } label: { Label(title, systemImage: icon).appFont(.body, weight: .semibold, design: .default).frame(maxWidth: .infinity).appMinHeight(42).foregroundStyle(type == value ? color : .primary).background(type == value ? color.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain)
    }
    private func iconChoice(_ icon: String) -> some View {
        Button { emoji = icon } label: { Text(icon).appFont(.dialogTitle, weight: .regular, design: .default).frame(width: MacUI.space(33), height: MacUI.space(33)).background(emoji == icon ? MacAccent.color(color).opacity(0.12) : .gray.opacity(0.06), in: Circle()).appPadding(2).overlay(Circle().strokeBorder(emoji == icon ? MacAccent.color(color).opacity(0.5) : .clear)) }.buttonStyle(.plain).accessibilityLabel("分类 emoji " + icon).accessibilityIdentifier("categoryEmoji-" + icon).accessibilityValue(emoji == icon ? "已选中" : "未选中")
    }
    private func select(_ row: Category?) {
        selectedID = row?.id; name = row.map { MacOverviewStyle.category($0.name) } ?? ""
        let style = row.map { MacCategoryCatalog.style(name: $0.name, type: $0.type) } ?? MacCategoryStyle()
        symbol = style.symbol; emoji = row.map { MacCategoryCatalog.emoji(name: $0.name, type: $0.type) } ?? "🏷️"; color = style.color; error = nil; message = nil
    }
    private func save() {
        do {
            guard MacCategoryEmoji.isValid(emoji) else { throw MacSettingsFailure.invalid("请选择或输入一个 emoji") }; var clean = try MacTransactionCRUD.validatedCategory(name)
            var order = selected.map { MacCategoryCatalog.style(name: $0.name, type: type).order } ?? ((rows.map { MacCategoryCatalog.style(name: $0.name, type: type).order }.max() ?? -1) + 1)
            if let selected {
                let oldID = selected.id, oldName = selected.name
                if clean != oldName && clean != MacOverviewStyle.category(oldName) {
                    let target = categories.first { $0.deletedAt == nil && $0.type == type && $0.id != oldID && $0.name.localizedCaseInsensitiveCompare(clean) == .orderedSame }
                    if let target { order = MacCategoryCatalog.style(name: target.name, type: type).order }
                    try MacDataManagement.rename(selected, to: clean, in: context)
                    selectedID = target?.id ?? oldID
                } else { clean = oldName }
            } else {
                let row = CategoryUsageHelper.ensureCategoryExists(name: clean, type: type, in: context, existingCategories: categories)
                try context.save(); selectedID = row?.id; clean = row?.name ?? clean
            }
            try MacCategoryCatalog.saveStyle(.init(symbol: symbol, color: color, order: order, emoji: emoji), name: clean, type: type)
            name = clean; error = nil; message = "分类已保存"
        } catch { context.rollback(); self.error = MacLocalization.error(error) }
    }
    private func move(_ row: Category, by offset: Int) {
        var list = rows; guard let index = list.firstIndex(where: { $0.id == row.id }), list.indices.contains(index + offset) else { return }
        list.swapAt(index, index + offset)
        do { for (index, item) in list.enumerated() { var style = MacCategoryCatalog.style(name: item.name, type: type); style.order = index; try MacCategoryCatalog.saveStyle(style, name: item.name, type: type) } }
        catch { self.error = MacLocalization.error(error) }
    }
}
