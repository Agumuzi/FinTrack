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
    var titles: [String] = []
    var onRowClick: (Int) -> Void = { _ in }

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
        var insetObservation: NSKeyValueObservation?
        var autoInsetObservation: NSKeyValueObservation?
        var headerQueued = false
        var aligningHeader = false
        var verticalOffset: CGFloat = 0
        var appliedWidths: [CGFloat] = []
        var userWidths: [CGFloat]?
        var lockedColumn: Int?
        var eventMonitor: Any?
        var dragColumn: Int?
        var dragStart = CGPoint.zero
        var dragWidths: [CGFloat] = []
        var pressedRow: Int?
        #if FINTRACK_LOCAL_VALIDATION
        var dragEvents = 0
        #endif
        init(_ parent: MacRecordsTableSizing) { self.parent = parent }
        deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) }; if let eventMonitor { NSEvent.removeMonitor(eventMonitor) } }
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
                verticalOffset = 0
                let clip = scroll.contentView
                clip.postsBoundsChangedNotifications = true
                insetObservation = clip.observe(\.contentInsets, options: [.new]) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.scheduleHeaderAlignment() }
                }
                autoInsetObservation = clip.observe(\.automaticallyAdjustsContentInsets, options: [.new]) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.scheduleHeaderAlignment() }
                }
                observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, !self.aligningHeader else { return }
                        if !clip.automaticallyAdjustsContentInsets {
                            self.verticalOffset = max(0, clip.bounds.minY + clip.contentInsets.top)
                        } else { self.scheduleHeaderAlignment() }
                    }
                })
                scroll.contentView.postsFrameChangedNotifications = true
                observers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.scheduleSizing() }
                })
                observers.append(NotificationCenter.default.addObserver(forName: NSTableView.columnDidResizeNotification, object: found, queue: .main) { [weak self] notification in
                    MainActor.assumeIsolated { self?.columnResized(notification) }
                })
            }
            if !(found.headerView is MacStableRecordsHeader) {
                let header = MacStableRecordsHeader(frame: found.headerView?.frame ?? NSRect(x: 0, y: 0, width: found.bounds.width, height: 32))
                found.headerView = header
            }
            if let header = found.headerView as? MacStableRecordsHeader {
                header.titles = parent.titles; header.headerFont = MacInterfaceFonts.font(size: MacUI.fontTier.bodySize, weight: .medium)
                let height = max(28, ceil(header.headerFont.ascender - header.headerFont.descender) + 12)
                if abs(header.frame.height-height)>0.5 {
                    found.headerView=nil
                    header.setFrameSize(NSSize(width:header.frame.width,height:height))
                    found.headerView=header
                    for column in found.tableColumns {column.headerCell.font=header.headerFont}
                    header.invalidateIntrinsicContentSize();scroll.tile()
                }
                scheduleHeaderAlignment()
                header.needsDisplay = true
                header.window?.invalidateCursorRects(for: header)
            }
            if eventMonitor == nil {
                eventMonitor = NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.leftMouseDragged,.leftMouseUp]) { [weak self] event in
                    guard let self, let table = self.table, event.window === table.window, let header = table.headerView else { return event }
                    let point = header.convert(event.locationInWindow,from:nil)
                    #if FINTRACK_LOCAL_VALIDATION
                    if event.type == .leftMouseDragged { self.dragEvents += 1 }
                    MacRecordSizingDiagnostics.shared.text = "dragEvents=\(self.dragEvents) event=\(event.type.rawValue) point=\(point) bounds=\(header.bounds) rects=\(table.tableColumns.indices.map { header.headerRect(ofColumn:$0).maxX }) widths=\(table.tableColumns.map(\.width))"
                    #endif
                    if event.type == .leftMouseDown {
                        if !header.bounds.contains(point) {
                            let row = table.row(at: table.convert(event.locationInWindow, from: nil))
                            self.pressedRow = row >= 0 ? row : nil
                            return event
                        }
                        self.pressedRow = nil
                        if self.parent.selecting && header.headerRect(ofColumn: 0).contains(point) { return event }
                        if let index = table.tableColumns.indices.dropLast().first(where: { abs(header.headerRect(ofColumn: $0).maxX - point.x) <= 7 }) {
                            self.dragColumn = index; self.dragStart = point; self.dragWidths = table.tableColumns.map(\.width)
                        }
                        // Non-sortable headers do not enter AppKit's highlighted/pressed
                        // cell tracking, which replaces SwiftUI's custom font while held.
                        return nil
                    }
                    if event.type == .leftMouseDragged && self.dragColumn == nil { self.pressedRow = nil }
                    if event.type == .leftMouseUp, self.dragColumn == nil {
                        defer { self.pressedRow = nil }
                        if let row = self.pressedRow, !self.parent.selecting, event.clickCount == 1,
                           event.modifierFlags.intersection([.command, .shift, .control]).isEmpty,
                           table.row(at: table.convert(event.locationInWindow, from: nil)) == row {
                            DispatchQueue.main.async { [weak self] in self?.parent.onRowClick(row) }
                        }
                    }
                    guard let index = self.dragColumn else { return event }
                    self.userWidths = self.dragWidths
                    self.userWidths?[index] = max(1,self.dragWidths[index]+point.x-self.dragStart.x)
                    self.lockedColumn = index; self.lastConfiguration = ""; self.sizeColumns()
                    if event.type == .leftMouseUp { self.dragColumn = nil }
                    return nil
                }
            }
            sizeColumns()
        }
        private func scheduleHeaderAlignment() {
            guard !aligningHeader, !headerQueued else { return }
            headerQueued = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }; self.headerQueued = false
                guard let table = self.table, let scroll = table.enclosingScrollView, let header = table.headerView else { return }
                let clip = scroll.contentView, height = header.frame.height
                self.aligningHeader = true
                defer { self.aligningHeader = false }
                if clip.automaticallyAdjustsContentInsets || abs(clip.contentInsets.top-height)>0.5 {
                    clip.automaticallyAdjustsContentInsets = false
                    var insets = clip.contentInsets; insets.top = height; clip.contentInsets = insets
                    clip.scroll(to: NSPoint(x:clip.bounds.minX,y:self.verticalOffset-height))
                    scroll.reflectScrolledClipView(clip)
                }
                #if FINTRACK_LOCAL_VALIDATION
                if ProcessInfo.processInfo.environment["FINTRACK_RECORD_SIZING_PROBE"] == "1" {
                    let row = table.convert(table.rect(ofRow:0),to:scroll), headerRect = header.convert(header.bounds,to:scroll)
                    let text = "firstRowY=\(row.minY) headerMaxY=\(headerRect.maxY) offset=\(self.verticalOffset) bounds=\(clip.bounds) header=\(header.frame)"
                    if MacRecordSizingDiagnostics.shared.text != text { MacRecordSizingDiagnostics.shared.text = text }
                }
                #endif
            }
        }
        private func scheduleSizing() {
            guard !applying, !queued else { return }
            queued = true
            DispatchQueue.main.async { [weak self] in self?.queued = false; self?.sizeColumns() }
        }
        private func columnResized(_ notification: Notification) {
            guard !applying, let table else { return }
            let event = NSApp.currentEvent?.type
            guard event == .leftMouseDragged || event == .leftMouseUp else { return }
            userWidths = table.tableColumns.map(\.width)
            if let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn { lockedColumn = table.tableColumns.firstIndex(of: column) }
            lastConfiguration = ""
            scheduleSizing()
        }
        private func sizeColumns() {
            guard !applying, let table, let scroll = table.enclosingScrollView else { return }
            let expected = (parent.compact ? 3 : 5) + (parent.selecting ? 1 : 0)
            guard table.tableColumns.count == expected else { return }
            let viewport = scroll.contentView.bounds.width
            guard viewport > 0 else { return }
            let configuration = "\(viewport)/\(parent.dateWidth)/\(parent.amountWidth)/\(parent.categoryWidth)/\(parent.compact)/\(parent.selecting)/\(parent.revision)"
            if configuration == lastConfiguration, appliedWidths.count == expected { return }
            applying = true; defer { applying = false }
            scroll.hasHorizontalScroller = false
            scroll.horizontalScrollElasticity = .none
            let spacing = table.intercellSpacing.width
            let existingSum = table.tableColumns.reduce(0) { $0 + $1.width }
            let inset = max(0, table.rect(ofColumn: expected-1).maxX - existingSum - spacing * CGFloat(expected-1))
            let available = max(1, viewport - spacing * CGFloat(expected-1) - inset)
            let key = "v141_record_columns.\(parent.compact ? "compact" : "full").\(parent.selecting)"
            let saved = MacPreferences.defaults.array(forKey: key)?.compactMap { ($0 as? NSNumber).map { CGFloat($0.doubleValue) } }
            var preferred: [CGFloat] = parent.compact ? [parent.dateWidth, parent.categoryWidth, parent.amountWidth] : [parent.dateWidth, parent.categoryWidth, 240, max(48, MacUI.fontTier.bodySize*2.1+24), parent.amountWidth]
            var minimum: [CGFloat] = parent.compact ? [parent.dateWidth, max(60,MacUI.fontTier.bodySize*2+30), parent.amountWidth] : [parent.dateWidth, max(60,MacUI.fontTier.bodySize*2+30), 80, max(48,MacUI.fontTier.bodySize*2.1+24),parent.amountWidth]
            if parent.selecting { preferred.insert(28,at:0); minimum.insert(28,at:0) }
            if let candidate = userWidths ?? saved, candidate.count == expected { preferred = candidate }
            else {
                let flexible = parent.compact ? (parent.selecting ? 2 : 1) : (parent.selecting ? 3 : 2)
                preferred[flexible] = max(minimum[flexible], available - preferred.enumerated().filter { $0.offset != flexible }.reduce(0) { $0 + $1.element })
            }
            let widths = MacRecordColumnLayout.fit(preferred: preferred, minimum: minimum, total: available, locked: lockedColumn)
            table.allowsColumnResizing = true
            table.columnAutoresizingStyle = .noColumnAutoresizing
            for (column,width) in zip(table.tableColumns,widths) {
                column.minWidth = 1; column.maxWidth = .greatestFiniteMagnitude
                column.resizingMask = .userResizingMask
                if abs(column.width-width) > 0.5 { column.width = width }
            }
            if abs(table.frame.width-viewport) > 0.5 { table.setFrameSize(NSSize(width:viewport,height:table.frame.height)) }
            if userWidths != nil { userWidths = widths; MacPreferences.defaults.set(widths.map(Double.init),forKey:key) }
            lockedColumn = nil
            lastConfiguration = configuration; appliedWidths = widths
            scheduleHeaderAlignment()
            table.headerView?.needsDisplay = true
            if let header = table.headerView { header.window?.invalidateCursorRects(for: header) }
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

/// One consistent font and only internal resize boundaries; no native pressed-cell fallback.
final class MacStableRecordsHeader: NSTableHeaderView {
    var titles: [String] = []
    var headerFont = NSFont.systemFont(ofSize: 14, weight: .medium)
    override var intrinsicContentSize: NSSize {NSSize(width:NSView.noIntrinsicMetric,height:max(28,ceil(headerFont.ascender-headerFont.descender)+12))}
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill(); dirtyRect.fill()
        guard let tableView else { return }
        for index in tableView.tableColumns.indices {
            let rect = headerRect(ofColumn: index)
            guard rect.intersects(dirtyRect) else { continue }
            let title = titles.indices.contains(index) ? titles[index] : tableView.tableColumns[index].title
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
            paragraph.alignment = index == tableView.tableColumns.count - 1 ? .right : .left
            let height = ceil(headerFont.ascender - headerFont.descender) + 3
            let textRect = NSRect(x: rect.minX + 10, y: rect.minY + (rect.height - height) / 2, width: max(0, rect.width - 20), height: height)
            (title as NSString).draw(in: textRect, withAttributes: [.font: headerFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph])
            if index < tableView.tableColumns.count - 1 {
                NSColor.separatorColor.setFill(); NSRect(x: rect.maxX - 0.5, y: rect.minY + 7, width: 1, height: max(0, rect.height - 14)).fill()
            }
        }
    }
    override func mouseDown(with event: NSEvent) { /* Divider dragging belongs to the coordinator. */ }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
        guard let tableView else { return }
        for index in tableView.tableColumns.indices.dropLast() {
            let rect = headerRect(ofColumn: index)
            addCursorRect(NSRect(x: rect.maxX - 6, y: rect.minY, width: 12, height: rect.height), cursor: .resizeLeftRight)
        }
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

/// Fit internal columns into one fixed viewport, preserving the dragged column.
nonisolated enum MacRecordColumnLayout {
    static func fit(preferred: [CGFloat], minimum: [CGFloat], total: CGFloat, locked: Int? = nil) -> [CGFloat] {
        guard !preferred.isEmpty, preferred.count == minimum.count, total.isFinite, total > 0 else { return [] }
        let count = preferred.count
        let safeMin = minimum.map { max(1, $0.isFinite ? $0 : 1) }
        let minSum = safeMin.reduce(0,+)
        if minSum > total { return safeMin.map { $0 / minSum * total } }
        var result = zip(preferred,safeMin).map { max($1,$0.isFinite ? $0 : $1) }
        let movable = result.indices.filter { $0 != locked }
        if let locked, result.indices.contains(locked) { result[locked] = min(result[locked], total - movable.reduce(0) { $0 + safeMin[$1] }) }
        var remainder = total - result.reduce(0,+)
        if remainder > 0 {
            let receivers = movable.isEmpty ? Array(result.indices) : movable
            let weight = receivers.reduce(0) { $0 + result[$1] }
            for index in receivers { result[index] += remainder * result[index] / max(weight,1) }
        } else if remainder < 0 {
            let donors = movable.isEmpty ? Array(result.indices) : movable
            let capacity = donors.reduce(0) { $0 + result[$1]-safeMin[$1] }
            for index in donors { result[index] -= min(-remainder,capacity) * (result[index]-safeMin[index]) / max(capacity,1) }
            remainder = total-result.reduce(0,+)
            if remainder < -0.001, let locked, result.indices.contains(locked) { result[locked] += remainder }
        }
        result[count-1] += total-result.reduce(0,+)
        return result
    }
}

#if FINTRACK_LOCAL_VALIDATION
@MainActor final class MacRecordSizingDiagnostics: ObservableObject {
    static let shared = MacRecordSizingDiagnostics()
    @Published var text = "No native header events"
}
struct MacRecordSizingDiagnosticsView: View {
    @ObservedObject var state = MacRecordSizingDiagnostics.shared
    var body: some View {
        if ProcessInfo.processInfo.environment["FINTRACK_RECORD_SIZING_PROBE"] == "1" {
            Text(state.text).font(.system(size:8)).padding(4).background(.yellow).accessibilityIdentifier("recordSizingDiagnostics")
        }
    }
}
#endif
