import SwiftUI
import AppKit

/// Device-local window geometry; isolated tests use their own preference suite.
struct MacMainWindowMemory: NSViewRepresentable {
    static let key = "v143_main_window_frame"
    static func fitted(_ frame: CGRect, screens: [CGRect]) -> CGRect? {
        guard frame.width.isFinite, frame.height.isFinite, frame.minX.isFinite, frame.minY.isFinite,
              frame.width >= 800, frame.height >= 600, !screens.isEmpty else { return nil }
        let screen = screens.max { $0.intersection(frame).width * $0.intersection(frame).height < $1.intersection(frame).width * $1.intersection(frame).height } ?? screens[0]
        let width = min(frame.width, screen.width), height = min(frame.height, screen.height)
        return CGRect(x: min(max(frame.minX, screen.minX), screen.maxX - width), y: min(max(frame.minY, screen.minY), screen.maxY - height), width: width, height: height)
    }
    final class Probe: NSView {
        var attached: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if let window { attached?(window) } }
    }
    final class Coordinator {
        weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var restoring = false
        deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
        func attach(_ window: NSWindow) {
            guard self.window !== window, !window.isSheet else { return }
            self.window = window
            // Explicit fixture dimensions take precedence over a remembered test frame.
            let explicitFixture = MacPreferences.isTesting && ProcessInfo.processInfo.environment["FINTRACK_TEST_WINDOW_WIDTH"] != nil
            if !explicitFixture, let text = MacPreferences.defaults.string(forKey: MacMainWindowMemory.key),
               let rect = MacMainWindowMemory.fitted(NSRectFromString(text), screens: NSScreen.screens.map(\.visibleFrame)) {
                restoring = true; window.setFrame(rect, display: false); restoring = false
            }
            for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.save() } })
            }
            observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.save() } })
        }
        private func save() {
            guard !restoring, let window, !window.styleMask.contains(.fullScreen), window.frame.width >= 800, window.frame.height >= 600 else { return }
            MacPreferences.defaults.set(NSStringFromRect(window.frame), forKey: MacMainWindowMemory.key)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> Probe {
        let view = Probe(); view.attached = { [weak coordinator = context.coordinator] window in coordinator?.attach(window) }; return view
    }
    func updateNSView(_ view: Probe, context: Context) { if let window = view.window { context.coordinator.attach(window) } }
}
