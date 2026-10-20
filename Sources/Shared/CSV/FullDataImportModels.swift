import Foundation

struct FullDataImportPreview: Hashable {
    let sourceFileName: String
    let transactionCount: Int
    let recurringRuleCount: Int
    let depositCount: Int
    let loanCount: Int
    let goalCount: Int
    let profileCount: Int
    let categoryCount: Int
    let accountCount: Int

    var totalRecordCount: Int {
        transactionCount
            + recurringRuleCount
            + depositCount
            + loanCount
            + goalCount
            + profileCount
            + categoryCount
            + accountCount
    }
}

struct FullDataImportCommitResult: Hashable {
    let transactionCount: Int
    let recurringRuleCount: Int
    let depositCount: Int
    let loanCount: Int
    let goalCount: Int
    let profileCount: Int
    let categoryCount: Int
    let accountCount: Int

    var totalRecordCount: Int {
        transactionCount
            + recurringRuleCount
            + depositCount
            + loanCount
            + goalCount
            + profileCount
            + categoryCount
            + accountCount
    }
}
