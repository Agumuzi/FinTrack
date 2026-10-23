import SwiftUI

/// Time is edited through the same card menus as other choices, without a
/// platform date-field stepper competing with the application's design system.
struct MacTimeMenu: View {
    @AppStorage(MacInterfaceFonts.preferenceKey, store: MacPreferences.defaults) private var interfaceFont = ""
    @Binding var date: Date
    var identifier = "timeChoice"
    @State private var showing = false
    @State private var hour = 9
    @State private var minute = 0
    var body: some View {
        Button {
            hour = Calendar.current.component(.hour, from: date)
            minute = Calendar.current.component(.minute, from: date)
            showing = true
        } label: {
            HStack {
                Text(MacDisplayPreferences.time(date)).appFont(.body)
                Spacer(minLength: 12)
                Image(systemName: "chevron.down").appFont(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 12).frame(minHeight: MacInterfaceFonts.controlHeight())
                .background(MacOverviewStyle.card, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.gray.opacity(0.25))).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(identifier).accessibilityValue(MacDisplayPreferences.time(date))
            .popover(isPresented: $showing) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("选择时间").appFont(.section, weight: .semibold)
                    HStack(spacing: 10) {
                        MacSettingsMenu(selection: $hour, options: (0...23).map { (String(format: "%02d 时", $0), $0) }).frame(width: 110).accessibilityIdentifier(identifier + "Hour")
                        Text(":").foregroundStyle(.secondary)
                        MacSettingsMenu(selection: $minute, options: (0...59).map { (String(format: "%02d 分", $0), $0) }).frame(width: 110).accessibilityIdentifier(identifier + "Minute")
                    }
                    HStack {
                        Button("取消") { showing = false }; Spacer()
                        Button("完成") { date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date; showing = false }.keyboardShortcut(.defaultAction)
                    }
                }.padding(18).background(MacPopoverKeyboardActions(cancel: { showing = false }, done: { date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date; showing = false }).frame(width: 0, height: 0))
            }
    }
}
