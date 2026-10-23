import SwiftUI
import AppKit

/// Consume dismissal keys at the visible popover, before an outer sheet's
/// Cancel/Save shortcut can act on them and discard or submit its draft.
struct MacPopoverKeyboardActions: NSViewRepresentable {
    var cancel: () -> Void
    var done: () -> Void
    func makeNSView(context: Context) -> KeyView { let view = KeyView(); view.cancel = cancel; view.done = done; return view }
    func updateNSView(_ view: KeyView, context: Context) { view.cancel = cancel; view.done = done }
    final class KeyView: NSView {
        var cancel: (() -> Void)?
        var done: (() -> Void)?
        private var monitor: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, window.isVisible,
                      event.window === window || event.window === window.parent || event.window === window.sheetParent,
                      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return event }
                if event.keyCode == 53 { self.cancel?(); return nil }
                if event.keyCode == 36 || event.keyCode == 76 { self.done?(); return nil }
                return event
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
