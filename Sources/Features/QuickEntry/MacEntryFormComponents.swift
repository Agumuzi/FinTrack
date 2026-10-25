import SwiftUI

/// Shared presentation for the main editor and its narrower menu-bar form.
struct MacEntryField<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment:.leading,spacing:MacUI.space(7)) {
            Text(title).appFont(.body,weight:.medium).foregroundStyle(.secondary)
            content
        }
    }
}

struct MacEntryFieldBorder: ViewModifier {
    func body(content: Content) -> some View {
        content.background(MacOverviewStyle.card,in:RoundedRectangle(cornerRadius:9))
            .overlay(RoundedRectangle(cornerRadius:9).strokeBorder(.gray.opacity(0.25)))
    }
}

struct MacEntryTypeSwitcher: View {
    @Binding var type: TransactionType
    var prefix: String
    var body: some View {
        HStack(spacing:0) {
            option(.expense,title:"支出",icon:"arrow.up.right",color:.red)
            option(.income,title:"收入",icon:"arrow.down",color:.green)
        }.background(MacOverviewStyle.filters,in:RoundedRectangle(cornerRadius:12))
    }
    private func option(_ value: TransactionType,title:String,icon:String,color:Color) -> some View {
        Button { type = value } label: {
            HStack(spacing:MacUI.space(10)) {
                Image(systemName:icon).foregroundStyle(color)
                Text(title).foregroundStyle(type == value ? color : .primary)
            }.appFont(.body,weight:.semibold).frame(maxWidth:.infinity).appMinHeight(40)
                .background(color.opacity(type == value ? 0.07 : 0.035),in:RoundedRectangle(cornerRadius:11))
                .overlay(RoundedRectangle(cornerRadius:11).strokeBorder(type == value ? color.opacity(0.15) : .clear))
                .contentShape(Rectangle())
        }.buttonStyle(MacInteractiveButtonStyle()).accessibilityLabel(title).accessibilityValue(type == value ? "已选中" : "未选中")
            .accessibilityIdentifier(prefix + (value == .expense ? "TypeExpense" : "TypeIncome"))
    }
}

struct MacEntryExchangeCard<Content: View>: View {
    @Binding var expanded: Bool
    var source: String
    var base: String
    var identifier: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment:.leading,spacing:MacUI.space(12)) {
            Button { expanded.toggle() } label: {
                HStack(spacing:MacUI.space(11)) {
                    Image(systemName:"info.circle").appIconFont(22)
                    VStack(alignment:.leading,spacing:MacUI.space(4)) {
                        Text("记账金额与汇率（可选）").appFont(.body,weight:.semibold)
                        Text(source.uppercased() + " → " + base + (source.uppercased() == base ? " · 同币种，无需换算" : " · 核对交易日汇率后保存"))
                            .appFont(.caption,weight:.regular).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }
                    Spacer(minLength:4)
                    Image(systemName:expanded ? "chevron.up" : "chevron.down").appFont(.body,weight:.semibold)
                }.contentShape(Rectangle())
            }.buttonStyle(MacInteractiveButtonStyle()).accessibilityIdentifier(identifier)
            if expanded { Divider(); content }
        }.appPadding(14).modifier(MacEntryFieldBorder())
    }
}

enum MacEntryDateDisplay {
    static func string(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier:"zh_CN"); formatter.dateFormat = "yyyy-MM-dd（EEE）"
        return formatter.string(from:date)
    }
}
