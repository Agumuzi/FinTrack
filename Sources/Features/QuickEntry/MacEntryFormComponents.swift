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
    @ObservedObject private var localizationState = LocalizationController.shared
    @Binding var type: TransactionType
    var prefix: String
    var body: some View {
        HStack(spacing:0) {
            option(.expense,title:L10n.text("mac.entryFormComponents.option.e679096865"),icon:"arrow.up.right",color:.red)
            option(.income,title:L10n.text("mac.entryFormComponents.option.117d8f914d"),icon:"arrow.down",color:.green)
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
        }.buttonStyle(MacInteractiveButtonStyle()).accessibilityLabel(title).accessibilityValue(type == value ? L10n.text("mac.entryFormComponents.option.a737fd72b0") : L10n.text("mac.entryFormComponents.option.0e0c21de69"))
            .accessibilityIdentifier(prefix + (value == .expense ? "TypeExpense" : "TypeIncome"))
    }
}

struct MacEntryExchangeCard<Content: View>: View {
    @ObservedObject private var localizationState = LocalizationController.shared
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
                        Text(L10n.text("mac.entryFormComponents.body.3bcac30912")).appFont(.body,weight:.semibold)
                        Text(source.uppercased() + " → " + base + (source.uppercased() == base ? L10n.text("mac.entryFormComponents.body.1ed672beb0") : L10n.text("mac.entryFormComponents.body.af4bb9cd4c")))
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
        let formatter = DateFormatter(); formatter.locale = L10n.locale; formatter.dateFormat = "yyyy-MM-dd（EEE）"
        return formatter.string(from:date)
    }
}
