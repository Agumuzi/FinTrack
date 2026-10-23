import SwiftUI
import UniformTypeIdentifiers

enum MacCurrencyDirectory {
    static func ordered(_ codes: [String], base: String) -> [String] {
        var seen: Set<String> = [base]
        return [base] + codes.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    static func moved(_ codes: [String], code: String, before target: String?, base: String) -> [String] {
        var result = ordered(codes, base: base)
        guard code != base, target != base, code != target, let source = result.firstIndex(of: code), target == nil || result.contains(target!) else { return result }
        result.remove(at: source)
        result.insert(code, at: target.flatMap { result.firstIndex(of: $0) } ?? result.endIndex)
        return result
    }
}

struct MacDirectoryDrop: DropDelegate {
    let target: String?
    let base: String
    @Binding var dragged: String?
    @Binding var order: [String]
    var save: ([String]) -> Void
    func validateDrop(info: DropInfo) -> Bool { dragged != nil && info.hasItemsConforming(to: [.text]) }
    func dropEntered(info: DropInfo) {
        guard let dragged else { return }
        withAnimation(.easeInOut(duration: 0.18)) { order = MacCurrencyDirectory.moved(order, code: dragged, before: target, base: base) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { guard dragged != nil else { return false }; save(order); dragged = nil; order = []; return true }
}
