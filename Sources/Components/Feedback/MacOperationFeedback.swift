import SwiftUI

/// Transient operation results. Financial confirmation dialogs keep their own
/// explicit confirmation flow; dismissing this notice never repeats an action.
@MainActor
final class MacOperationFeedbackCenter: ObservableObject {
    enum Kind: Equatable {
        case success, warning, failure
        var emoji: String {
            switch self { case .success: "✅"; case .warning: "⚠️"; case .failure: "❌" }
        }
    }
    enum Location: Equatable { case workspace, csvPreview, nativePreview }
    struct Notice {
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
        content.overlay {
            if let notice = center.notice, notice.location == location {
                GeometryReader { geometry in
                    ZStack {
                        Color.black.opacity(0.12).contentShape(Rectangle())
                            .onTapGesture { center.notice = nil }
                            .accessibilityLabel("关闭结果提示")
                            .accessibilityIdentifier("operationFeedbackBackdrop")
                        VStack(alignment:.leading,spacing:16) {
                            Text(notice.kind.emoji + " " + notice.title)
                                .appFont(.section,weight:.semibold)
                                .accessibilityIdentifier("operationFeedbackTitle")
                            Text(notice.message).appFont(.body).textSelection(.enabled)
                                .fixedSize(horizontal:false,vertical:true).lineLimit(8)
                                .frame(maxWidth:.infinity,alignment:.leading)
                                .accessibilityIdentifier("operationFeedbackMessage")
                            HStack {
                                Spacer()
                                Button("完成") { center.notice = nil }
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
