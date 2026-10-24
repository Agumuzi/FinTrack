import SwiftUI
import AppKit

/// Keep the native table's actual column widths inside its clip view. SwiftUI
/// retains flexible column widths when a selection column is inserted; sizing
/// the NSTableColumns also accounts for the native padding and scroll gutter.
struct MacRecordsTableSizing: NSViewRepresentable {
    var dateWidth: CGFloat
    var amountWidth: CGFloat
    var categoryWidth: CGFloat
    var compact: Bool
    var selecting: Bool
    var revision: String

    final class Probe: NSView {
        var update: (() -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); update?() }
    }
    final class Coordinator: NSObject {
        var parent: MacRecordsTableSizing
        weak var probe: Probe?
        weak var table: NSTableView?
        var observers: [NSObjectProtocol] = []
        var applying = false
        var queued = false
        var lastConfiguration = ""
        var appliedWidths: [CGFloat] = []
        init(_ parent: MacRecordsTableSizing) { self.parent = parent }
        deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }
        private func findTable(_ view: NSView) -> NSTableView? {
            if let table = view as? NSTableView { return table }
            for child in view.subviews { if let result = findTable(child) { return result } }
            return nil
        }
        func update() {
            guard let probe, probe.window != nil else { return }
            var ancestor: NSView? = probe.superview, found: NSTableView?
            for _ in 0..<6 {
                guard let view = ancestor else { break }
                if let value = findTable(view) { found = value; break }
                ancestor = view.superview
            }
            guard let found, let scroll = found.enclosingScrollView else { return }
            if table !== found {
                for observer in observers { NotificationCenter.default.removeObserver(observer) }
                observers.removeAll(); lastConfiguration = ""; appliedWidths = []
                table = found
                scroll.contentView.postsBoundsChangedNotifications = true
                observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.scheduleSizing() }
                })
                observers.append(NotificationCenter.default.addObserver(forName: NSTableView.columnDidResizeNotification, object: found, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.scheduleSizing() }
                })
            }
            sizeColumns()
        }
        private func scheduleSizing() {
            guard !applying, !queued else { return }
            queued = true
            DispatchQueue.main.async { [weak self] in self?.queued = false; self?.sizeColumns() }
        }
        private func sizeColumns() {
            guard !applying, let table, let scroll = table.enclosingScrollView else { return }
            let expected = (parent.compact ? 3 : 5) + (parent.selecting ? 1 : 0)
            guard table.tableColumns.count == expected else { return }
            let viewport = scroll.contentView.bounds.width
            guard viewport > 0 else { return }
            let configuration = "\(viewport)/\(parent.dateWidth)/\(parent.amountWidth)/\(parent.categoryWidth)/\(parent.compact)/\(parent.selecting)/\(parent.revision)"
            if configuration == lastConfiguration, appliedWidths.count == expected,
               zip(table.tableColumns, appliedWidths).allSatisfy({ abs($0.width - $1) < 0.5 }) { return }
            applying = true; defer { applying = false }
            // Keep amount and category close to their content widths; notes
            // absorb spare space and the exact native inset correction.
            let spacing = table.intercellSpacing.width
            let available = max(1, viewport - spacing * CGFloat(max(0, expected - 1)))
            let check: CGFloat = parent.selecting ? 36 : 0
            let date = parent.dateWidth + 12
            let currency: CGFloat = parent.compact ? 0 : 62
            let remaining = max(1, available - check - date - currency)
            let amount = min(parent.amountWidth + 12, max(50, remaining - 46))
            let noteMinimum: CGFloat = parent.compact ? 0 : 80
            let category = max(30, min(parent.categoryWidth + 12, remaining - amount - noteMinimum))
            let note = max(1, remaining - amount - category)
            var widths: [CGFloat] = parent.selecting ? [check, date, parent.compact ? remaining - amount : category] : [date, parent.compact ? remaining - amount : category]
            if !parent.compact { widths += [note, currency] }
            widths.append(amount)
            table.columnAutoresizingStyle = .noColumnAutoresizing
            for (column, width) in zip(table.tableColumns, widths) {
                column.minWidth = 1; column.maxWidth = .greatestFiniteMagnitude
                if abs(column.width - width) > 0.5 { column.width = width }
            }
            if abs(table.frame.width - viewport) > 0.5 { table.setFrameSize(NSSize(width: viewport, height: table.frame.height)) }
            // Inset style adds margins beyond intercellSpacing. Remove their
            // exact measured overflow from the flexible interior column.
            let overflow = table.rect(ofColumn: expected - 1).maxX - viewport
            if overflow > 0 {
                let flexible = parent.compact ? (parent.selecting ? 2 : 1) : (parent.selecting ? 3 : 2)
                let column = table.tableColumns[flexible]
                column.width = max(1, column.width - overflow)
            }
            lastConfiguration = configuration; appliedWidths = table.tableColumns.map(\.width)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> Probe {
        let view = Probe(); context.coordinator.probe = view
        view.update = { [weak coordinator = context.coordinator] in DispatchQueue.main.async { coordinator?.update() } }
        return view
    }
    func updateNSView(_ view: Probe, context: Context) {
        context.coordinator.parent = self
        DispatchQueue.main.async { context.coordinator.update() }
    }
}

/// A separate native checkbox remains reachable in the accessibility tree;
/// NSTableHeaderView normally exposes only its own column header cells.
struct MacRecordsSelectAllCheckbox: NSViewRepresentable {
    var state: Int
    var action: () -> Void
    final class Coordinator: NSObject {
        var parent: MacRecordsSelectAllCheckbox
        init(_ parent: MacRecordsSelectAllCheckbox) { self.parent = parent }
        @objc func toggle() { parent.action() }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: context.coordinator, action: #selector(Coordinator.toggle))
        button.allowsMixedState = true
        button.setAccessibilityLabel("全选筛选结果")
        button.setAccessibilityIdentifier("recordSelectAllHeader")
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        button.state = state == 2 ? .on : state == 1 ? .mixed : .off
    }
}
