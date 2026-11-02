# Localization writing guide

Write for the target-language user and the actual task. Chinese is context, not a sentence template. English is the resource base; every later language needs its own terminology review and screenshots.

- Prefer familiar product terms and short actions: **Goals**, **Upcoming**, **Most Used**, **Decimal Places**, **Back Up Now**. Remove words already supplied by the page context.
- Use established abbreviations only when they preserve the exact concept. **CSV**, **USD** and **FX** are appropriate in relevant contexts. Do not invent abbreviations to fit a field. Do not relabel nominal interest as APR or APY, or a cash amount as yield.
- Preserve financial distinctions: **principal**, **interest**, **balance**, **net worth**, **forecast**, **posted**, **received**, and **outstanding** are separate concepts. A pending transaction is not a confirmed bank payment.
- Use **Interest to Collect** for outstanding interest across all scheduled years; **2026 Interest** for the planned-year total; **Future Interest** for outstanding interest from next year onward. Never label the first card as all-time earnings, because it excludes money already received.
- Keep complete sentences and plural rules in resources. Do not concatenate translated nouns, suffixes, or sentence fragments. Format dates using the effective application locale; retain explicit user-selected numeric formats.
- Short labels must remain clear without reading a tooltip. Use help text for scope and calculation explanations, not to repair a misleading label. Use real layout changes when text needs more room; do not depend on tiny type, clipped words, or forced abbreviations.
- Keep each frozen key stable when copy changes. Add scoped keys for genuinely new contexts and register them. Never translate persisted identities, user-authored names, CSV field names, receipt markers, or signed data in place.

## Core glossary

| Meaning | English UI | 简体中文 | Context |
|---|---|---|---|
| Individual ledger entry | Transaction | 账目 / 交易 | Choose the existing page-specific Chinese term. |
| Currency used by the ledger | Base Currency | 本位币 | Different from a payment's original currency. |
| Currency originally entered | Original Currency | 原币种 | Never sum different currencies. |
| Initial funds invested in a deposit | Principal | 本金 | Excluded from interest cards. |
| Interest confirmed as received | Received | 已到账 | Explicit manual posting or reconciled receipt. |
| Interest still due | Outstanding | 未到账 | Includes overdue and explicit partial-payment remainders. |
| Automatically created estimate | Pending Review | 待核对 | Not a payment confirmation. |
| Scheduled payment date | Payment Date | 计划结息日期 | Determines the interest card's year. |
| Total assets less liabilities | Net Worth | 净资产 | Keep separate from available balance and deposit principal. |
| Compare whole years | Year over Year | 年度对比 | Do not shorten to YoY where the audience may not know it. |
| Same month in different years | Same Month, Different Year | 同月跨年 | User chooses the reference month and comparison year. |

For each language pack, deliver a language-specific glossary, unresolved terminology questions, parameter validation, and screenshots at supported widths and scales. Existing Russian remains an inactive draft in v1.5; this guide does not authorize a new language release.
