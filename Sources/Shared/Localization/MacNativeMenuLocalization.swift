import AppKit
import Combine

/// Updates titles only. AppKit retains actions, delegates, validation and shortcuts.
@MainActor final class MacNativeMenuLocalization {
    static let shared = MacNativeMenuLocalization()
    private var subscriptions: [AnyCancellable] = []
    private var installed = false
    private let roots: [String:String] = ["File":"file","文件":"file","Файл":"file","Edit":"edit","编辑":"edit","Правка":"edit","View":"view","显示":"view","Вид":"view","Window":"window","窗口":"window","Окно":"window","Help":"help","帮助":"help","Справка":"help"]
    private let actions: [String:String] = ["orderFrontStandardAboutPanel:":"about","hide:":"hide","hideOtherApplications:":"hideOthers","unhideAllApplications:":"showAll","terminate:":"quit","undo:":"undo","redo:":"redo","cut:":"cut","copy:":"copy","paste:":"paste","pasteAsPlainText:":"pasteStyle","delete:":"delete","selectAll:":"selectAll","performClose:":"close","performMiniaturize:":"minimize","performZoom:":"zoom","arrangeInFront:":"front"]
    func install() {
        guard !installed else{return}; installed=true
        for name in [LocalizationController.didChange,NSApplication.didBecomeActiveNotification,NSWindow.didBecomeKeyNotification,NSMenu.didBeginTrackingNotification] {
            subscriptions.append(NotificationCenter.default.publisher(for:name).receive(on:DispatchQueue.main).sink { [weak self] _ in self?.refresh() })
        }
        DispatchQueue.main.async { self.refresh() }
    }
    func refresh() { if let menu=NSApp.mainMenu { apply(to:menu) } }
    func apply(to menu:NSMenu, root:Bool = true) {
        for item in menu.items {
            if root, let key=roots[item.title] ?? item.submenu.flatMap({ roots[$0.title] }) {
                let title=L10n.text("menu.native."+key)
                if item.title != title { item.title=title }
                if item.submenu?.title != title { item.submenu?.title=title }
            }
            if let selector=item.action, let key=actions[NSStringFromSelector(selector)] {
                let title=L10n.text("menu.native."+key)
                if item.title != title { item.title=title }
            }
            if let submenu=item.submenu {
                if submenu === NSApp.servicesMenu { item.title=L10n.text("menu.native.services") }
                apply(to:submenu,root:false)
            }
        }
    }
}
