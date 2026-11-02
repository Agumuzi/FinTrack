import Foundation

/// Historical data identities, not translation resources. Never translate these
/// tokens or rewrite stored category names when the display language changes.
nonisolated enum MacLegacyCategoryIdentity {
    static let loanAliases = ["Loan", "贷款"]
    static let depositAliases = ["Deposit", "存款"]
}
