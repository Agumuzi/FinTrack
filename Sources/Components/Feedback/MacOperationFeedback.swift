import SwiftUI

/// Transient operation results. Financial confirmation dialogs keep their own
/// explicit confirmation flow; dismissing this notice never repeats an action.
@MainActor
final class MacOperationFeedbackCenter: ObservableObject {
    enum Kind: Equatable {
        case success, warning, failure
        var symbol: String {
            switch self { case .success: "checkmark.circle.fill"; case .warning: "exclamationmark.triangle.fill"; case .failure: "xmark.circle.fill" }
        }
        var color: Color {
            switch self { case .success: .green; case .warning: .orange; case .failure: .red }
        }
    }
    enum Location: Equatable { case workspace, csvPreview, nativePreview }
    struct Notice: Identifiable {
        let id = UUID()
        var kind: Kind
        var title: String
        var message: String
        var location: Location = .workspace
    }
    @Published var notice: Notice?
    func show(_ kind: Kind, title: String, message: String, location: Location = .workspace) {
        notice = Notice(kind:kind,title:title,message:message,location:location)
    }
}

struct MacOperationFeedbackPresenter: ViewModifier {
    @ObservedObject var center: MacOperationFeedbackCenter
    var location: MacOperationFeedbackCenter.Location = .workspace
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if let notice = center.notice, notice.location == location, notice.kind == .success {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: notice.kind.symbol).foregroundStyle(notice.kind.color).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(notice.title).appFont(.body, weight: .semibold).accessibilityIdentifier("operationFeedbackTitle")
                        Text(notice.message).appFont(.caption).foregroundStyle(.secondary).accessibilityIdentifier("operationFeedbackMessage")
                    }
                    Spacer()
                    Button(L10n.text("mac.operationFeedback.GeometryReader.c0b3fbff51"), systemImage: "xmark") { center.notice = nil }
                        .labelStyle(.iconOnly).buttonStyle(.plain).accessibilityIdentifier("dismissOperationFeedback")
                }.padding(10).background(.regularMaterial)
                    .accessibilityIdentifier("operationFeedback")
                    .task(id: notice.id) {
                        do { try await Task.sleep(for: .seconds(8)) } catch { return }
                        if center.notice?.id == notice.id { center.notice = nil }
                    }
            }
        }.overlay {
            if let notice = center.notice, notice.location == location, notice.kind != .success {
                GeometryReader { geometry in
                    ZStack {
                        Color.black.opacity(0.12).contentShape(Rectangle())
                            .onTapGesture { center.notice = nil }
                            .accessibilityLabel(L10n.text("mac.operationFeedback.GeometryReader.cc74346897"))
                            .accessibilityIdentifier("operationFeedbackBackdrop")
                        VStack(alignment:.leading,spacing:16) {
                            HStack(spacing: 9) {
                                Image(systemName: notice.kind.symbol).appIconFont(20, weight: .semibold).foregroundStyle(notice.kind.color)
                                Text(notice.title).appFont(.section,weight:.semibold)
                            }.accessibilityElement(children: .combine)
                                .accessibilityIdentifier("operationFeedbackTitle")
                            Text(notice.message).appFont(.body).textSelection(.enabled)
                                .fixedSize(horizontal:false,vertical:true).lineLimit(8)
                                .frame(maxWidth:.infinity,alignment:.leading)
                                .accessibilityIdentifier("operationFeedbackMessage")
                            HStack {
                                Spacer()
                                Button(L10n.text("mac.operationFeedback.GeometryReader.c0b3fbff51")) { center.notice = nil }
                                    .buttonStyle(MacSettingsButtonStyle(primary:true))
                                    .keyboardShortcut(.defaultAction)
                                    .accessibilityIdentifier("dismissOperationFeedback")
                            }
                        }
                        .padding(22).frame(width:min(420,max(260,geometry.size.width-52)))
                        .background(MacOverviewStyle.card,in:RoundedRectangle(cornerRadius:16))
                        .overlay(RoundedRectangle(cornerRadius:16).strokeBorder(.primary.opacity(0.1)))
                        .shadow(color:.black.opacity(0.18),radius:24,y:8)
                        .contentShape(RoundedRectangle(cornerRadius:16)).onTapGesture {}
                        .focusable().focusEffectDisabled().focused($focused)
                        .onAppear { focused = true }
                        .onExitCommand { center.notice = nil }
                        .accessibilityElement(children:.contain)
                        .accessibilityIdentifier("operationFeedback")
                    }.frame(width:geometry.size.width,height:geometry.size.height)
                }
            }
        }
    }
}
