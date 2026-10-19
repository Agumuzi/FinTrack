import SwiftUI
import SwiftData

struct MacCategoryManagementView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.name) private var categories: [Category]
    @State private var type = "Expense"
    @State private var name = ""
    @State private var selected: Category?
    @State private var confirmRename = false
    @State private var removing: Category?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(14)) {
            Text("Manage categories").appFont(.dialogTitle, weight: .semibold).accessibilityIdentifier("categoryManagementTitle")
            Picker("Type", selection: $type) {
                Text("Expense").tag("Expense"); Text("Income").tag("Income")
            }.pickerStyle(.segmented).onChange(of: type) { selected = nil; name = "" }
            List(categories.filter { $0.deletedAt == nil && $0.type == type }, id: \.id) { item in
                HStack {
                    Text(CategoryUsageHelper.localizedDisplayName(for: item.name))
                    Spacer()
                    Button("Edit") { selected = item; name = item.name }
                    Button("Delete", role: .destructive) { removing = item }
                }.disabled(CategoryUsageHelper.isProtectedCategory(item))
            }
            TextField("Category", text: $name).accessibilityIdentifier("managedCategoryName")
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if selected != nil { Button("Cancel edit") { selected = nil; name = "" } }
                Button(selected == nil ? "Add" : "Save") {
                    if selected != nil { confirmRename = true }
                    else {
                        do {
                            let clean = try MacTransactionCRUD.validatedCategory(name)
                            _ = CategoryUsageHelper.ensureCategoryExists(name: clean, type: type, in: context, existingCategories: categories)
                            try context.save(); name = ""; error = nil
                        } catch { context.rollback(); self.error = MacLocalization.error(error) }
                    }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("saveManagedCategory")
            }
        }.appPadding(24).appPanel(width: 540, height: 480)
        .confirmationDialog("Update category references?", isPresented: $confirmRename) {
            Button("Rename or merge category") {
                guard let selected else { return }
                do { try MacDataManagement.rename(selected, to: name, in: context); self.selected = nil; name = ""; error = nil }
                catch { self.error = MacLocalization.error(error) }
            }
        } message: { Text("Existing records will use the new name. An existing matching category will be merged.") }
        .confirmationDialog("Delete category?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Delete", role: .destructive) {
                guard let removing else { return }
                context.delete(removing)
                do { try context.save(); self.removing = nil; selected = nil; name = "" }
                catch { context.rollback(); self.error = MacLocalization.error(error) }
            }
        } message: { Text("Existing records keep their category name.") }
    }
}
