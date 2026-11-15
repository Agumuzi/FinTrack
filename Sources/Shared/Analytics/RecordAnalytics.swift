import Foundation

enum RecordAnalytics {
    static func todayExpense(from transactions: [Transaction]) -> Double {
        transactions
            .filter { TransactionRecognition.isRealized($0) && $0.typedType == .expense }
            .reduce(0) { $0 + $1.baseAmount }
    }
}
