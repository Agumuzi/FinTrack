import SwiftUI
import AppKit

/// Escape must close the panel even when AppKit's field editor is first responder.
/// This is an in-process key handler scoped to this panel, never a global monitor.
struct MacMenuPanelKeyboard: NSViewRepresentable {
    var onEscape: () -> Void
    func makeNSView(context: Context) -> KeyboardView {
        let view = KeyboardView(); view.onEscape = onEscape; return view
    }
    func updateNSView(_ view: KeyboardView, context: Context) { view.onEscape = onEscape }

    final class KeyboardView: NSView {
        var onEscape: (() -> Void)?
        private var monitor: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      event.keyCode == 53, event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return event }
                self.onEscape?()
                return nil
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
