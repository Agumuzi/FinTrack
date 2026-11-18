# Receipt accounting (v1.5.7)

Ordinary transaction notes are user text. A literal `[FTEstimated]` does not turn an ordinary transaction into a pending receipt. `TransactionRecognition` parses the existing deposit receipt identity; state flags are interpreted only after that identity, so text in a bank name cannot set the state. Damaged system identities remain pending review. No receipt identity, transaction amount, historical FX snapshot or user note is rewritten on upgrade.

Income/expense totals, overview scopes/categories/trends and period comparisons use realized transactions. Pending deposit receipts remain in the transaction list, labeled as pending review, and in the deposit interest overview. A partial confirmed amount is realized once; a later correction changes that same receipt rather than appending income. Principal returns stay internal liquidity events, never ordinary income.

Native backup and CSV interchange preserve all raw records, including pending receipts and their notes. Exported rows are records, not a realized-income report; summing every exported income row without interpreting receipt state will include estimates. Full restoration requires native backups, not CSV.

## Preserving previously confirmed cash

Old liquidity JSON did not distinguish note-based exclusion from receipt-based exclusion. Replacing its cash formula alone could alter the current cash balance after upgrade. At ledger opening, and inside a normal native restore transaction, a missing optional `recognitionAdjustment` is populated once with:

    adjustment = recognizedNet(existing rows) - oldNoteBasedNet(existing rows)
    cash = confirmedCash + recognizedNet - transactionBaseline - adjustment + movements

Thus cash before and after the bridge is identical. Confirmed cash, transaction baseline, calibration events, principal positions and transactions are unchanged. Newly initialized states use zero adjustment. Once frozen, ordinary note edits cannot change eligibility. New transactions follow the corrected rule. Historical discrepancies already absorbed into the old reference are not silently paid out again: users may explicitly calibrate cash after checking their bank balance.

This is a neutral compatibility addition to the existing version-1 JSON, not a SwiftData schema migration or batch recalculation of transaction amounts. Older decoders ignore the optional field. Journal rollback restores its original snapshot unchanged; the normal ledger-open bridge then runs before user writes. Base-currency conversion resets the bridge after deriving the new baseline from the preserved current cash.

Targeted regressions cover ordinary marker text, pending/partial/adjusted interest, unchanged receipt IDs and raw notes, principal returns, CSV/native restoration, base-currency conversion, old reference preservation and English/Chinese status copy. Real personal ledgers and real Keychain permissions are not test fixtures.

## Dedicated receipt review (v1.5.8)

Records details and deposit details share the same review window and service. The service resolves the persisted deposit ID and exact scheduled occurrence, checks the original/base snapshot and rejects missing, duplicate, deleted or damaged identities. Ordinary generated-posting CRUD remains locked. Saving updates the existing receipt ID, amount and review flags; its date, marker, user-note prefix, currencies and historical exchange rate stay intact. Partial payment is the cumulative amount received for that occurrence; later review replaces that cumulative amount, never adds another income row. Cancelling writes nothing.

A pending receipt dated on or before the latest cash confirmation/calibration may already be included in that bank balance. The review window defaults to **already included**, with an explicit choice to credit cash if the saved balance excluded it. Already-included confirmation adds one offsetting `interestAlreadyIncluded` liquidity event in the same save as the realized receipt. Thus income is recognized, cash does not double-count the historical payment, and subsequent corrections change cash only by their difference. The old baseline, confirmed cash, calibration events and principal movements are preserved. Existing recognition bridges are frozen before any write. The event uses the existing liquidity JSON schema and survives native backup/restore; CSV alone is not a full liquidity backup.
