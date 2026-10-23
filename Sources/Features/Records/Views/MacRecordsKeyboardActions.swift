import SwiftUI
import AppKit

struct MacRecordsKeyboardActions: NSViewRepresentable {
    var selectAll: () -> Void
    func makeNSView(context: Context) -> KeyView { let view = KeyView(); view.action = selectAll; return view }
    func updateNSView(_ view: KeyView, context: Context) { view.action = selectAll }
    final class KeyView: NSView {
        var action: (() -> Void)?
        private var monitor: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      event.keyCode == 0, event.modifierFlags.contains(.command),
                      event.modifierFlags.intersection([.control, .option, .shift]).isEmpty else { return event }
                // Text fields retain the system's ordinary Select All behavior.
                if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor { return event }
                self.action?(); return nil
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
