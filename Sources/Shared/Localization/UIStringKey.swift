import Foundation

enum UIStringKey {
    enum Common {
        static let add = "common.add"
        static let all = "common.all"
        static let back = "common.back"
        static let bank = "common.bank"
        static let category = "common.category"
        static let cash = "common.cash"
        static let configured = "common.configured"
        static let copy = "common.copy"
        static let creditCard = "common.creditCard"
        static let custom = "common.custom"
        static let customCategory = "common.customCategory"
        static let day = "common.day"
        static let delete = "common.delete"
        static let done = "common.done"
        static let expense = "common.expense"
        static let finish = "common.finish"
        static let income = "common.income"
        static let investment = "common.investment"
        static let language = "common.language"
        static let month = "common.month"
        static let noData = "common.noData"
        static let next = "common.next"
        static let none = "common.none"
        static let notSet = "common.notSet"
        static let ok = "common.ok"
        static let other = "common.other"
        static let week = "common.week"
        static let warnings = "common.warnings"
        static let year = "common.year"
        static let pairSummaryFormat = "common.pairSummaryFormat"
        static let tripleSummaryFormat = "common.tripleSummaryFormat"
    }

    enum Category {
        static let bonus = "category.bonus"
        static let deposit = "category.deposit"
        static let dining = "category.dining"
        static let expenseCategories = "category.expenseCategories"
        static let gift = "category.gift"
        static let health = "category.health"
        static let incomeCategories = "category.incomeCategories"
        static let investment = "category.investment"
        static let loan = "category.loan"
        static let manageCategories = "category.manageCategories"
        static let merge = "category.merge"
        static let mergeCategories = "category.mergeCategories"
        static let mergeCategoriesPromptFormat = "category.mergeCategoriesPromptFormat"
        static let newExpenseCategory = "category.newExpenseCategory"
        static let newIncomeCategory = "category.newIncomeCategory"
        static let other = "category.other"
        static let salary = "category.salary"
        static let shopping = "category.shopping"
        static let supermarket = "category.supermarket"
        static let transport = "category.transport"
        static let travel = "category.travel"
    }

    enum Insights {
        static let all = "insights.filter.all"
        static let allGoalsPausedOrAccomplished = "insights.goal.allPausedOrAccomplished"
        static let categoryBreakdownTitle = "insights.section.categoryBreakdown.title"
        static let compareLockedSubtitle = "insights.section.compare.lockedSubtitle"
        static let compareReadySubtitle = "insights.section.compare.readySubtitle"
        static let compareSectionTitle = "insights.section.compare.title"
        static let compareDetailTitle = "insights.compare.detail.title"
        static let compareDefaultRouteTitle = "insights.compare.route.default.title"
        static let compareCustomRouteTitle = "insights.compare.route.custom.title"
        static let compareRouteSectionTitle = "insights.compare.route.section.title"
        static let compareCurrentLabel = "insights.compare.label.current"
        static let compareCurrentDateTitle = "insights.compare.date.current"
        static let compareDeltaPercentFormat = "insights.compare.summary.deltaPercent.format"
        static let compareDeltaPercentNoBaseline = "insights.compare.summary.deltaPercent.noBaseline"
        static let compareDeclineDriversTitle = "insights.compare.drivers.decline.title"
        static let compareDriversSectionTitle = "insights.compare.drivers.section.title"
        static let compareExpenseCardTitle = "insights.compare.summary.expense.title"
        static let compareGrowthDriversTitle = "insights.compare.drivers.growth.title"
        static let compareLargestGapCardTitle = "insights.compare.summary.largestGap.title"
        static let compareNetCardTitle = "insights.compare.summary.net.title"
        static let compareNoDeclineDriversTitle = "insights.compare.drivers.decline.empty"
        static let compareNoGrowthDriversTitle = "insights.compare.drivers.growth.empty"
        static let comparePatternCardTitle = "insights.compare.pattern.card.title"
        static let comparePatternConcentratedFormat = "insights.compare.pattern.message.concentrated.format"
        static let comparePatternDeclineDriverFormat = "insights.compare.pattern.message.declineDriver.format"
        static let comparePatternGrowthDriverFormat = "insights.compare.pattern.message.growthDriver.format"
        static let comparePatternHigherBaseline = "insights.compare.pattern.message.higherBaseline"
        static let comparePatternInsufficientData = "insights.compare.pattern.message.insufficientData"
        static let comparePatternLowerBaseline = "insights.compare.pattern.message.lowerBaseline"
        static let comparePatternMinimalChange = "insights.compare.pattern.message.minimalChange"
        static let comparePatternMultiDriverChange = "insights.compare.pattern.message.multiDriverChange"
        static let comparePatternNoComparable = "insights.compare.pattern.message.noComparable"
        static let comparePatternSingleDriverDecrease = "insights.compare.pattern.message.singleDriverDecrease.format"
        static let comparePatternSingleDriverIncrease = "insights.compare.pattern.message.singleDriverIncrease.format"
        static let comparePatternSpread = "insights.compare.pattern.message.spread"
        static let comparePatternSectionTitle = "insights.compare.pattern.section.title"
        static let comparePreviousLabel = "insights.compare.label.previous"
        static let comparePreviousDateTitle = "insights.compare.date.previous"
        static let compareTargetSectionTitle = "insights.compare.target.section.title"
        static let comparePreviousYearFormat = "insights.compare.summary.previousYear.format"
        static let compareCurrentYearFormat = "insights.compare.summary.currentYear.format"
        static let compareSameMonthCardTitle = "insights.compare.sameMonth.card.title"
        static let compareSameMonthDriverDeclineFormat = "insights.compare.sameMonth.driver.decline.format"
        static let compareSameMonthDriverGrowthFormat = "insights.compare.sameMonth.driver.growth.format"
        static let compareSameMonthNoDriver = "insights.compare.sameMonth.driver.empty"
        static let compareSameMonthSectionTitle = "insights.compare.sameMonth.section.title"
        static let compareSamePeriodSubtitleFormat = "insights.compare.summary.samePeriod.format"
        static let compareSummarySectionTitle = "insights.compare.summary.section.title"
        static let compareTeaserCoverageFormat = "insights.section.compare.teaser.coverageFormat"
        static let compareTeaserHeadlineFormat = "insights.section.compare.teaser.headlineFormat"
        static let compareTeaserSubtitle = "insights.section.compare.teaser.subtitle"
        static let compareTeaserSummaryFormat = "insights.section.compare.teaser.summaryFormat"
        static let compareTeaserTitle = "insights.section.compare.teaser.title"
        static let compareTrendSectionTitle = "insights.compare.trend.section.title"
        static let compareTrendQuarterQ1 = "insights.compare.trend.quarter.q1"
        static let compareTrendQuarterQ2 = "insights.compare.trend.quarter.q2"
        static let compareTrendQuarterQ3 = "insights.compare.trend.quarter.q3"
        static let compareTrendQuarterQ4 = "insights.compare.trend.quarter.q4"
        static let categoryBreakdownLockedSubtitle = "insights.section.categoryBreakdown.lockedSubtitle"
        static let categoryBreakdownLockedTitle = "insights.section.categoryBreakdown.lockedTitle"
        static let categoryBreakdownNoDataSubtitle = "insights.section.categoryBreakdown.noDataSubtitle"
        static let categoryBreakdownNoDataTitle = "insights.section.categoryBreakdown.noDataTitle"
        static let depositBalanceSubtitle = "insights.card.depositBalance.subtitle"
        static let depositBalanceTitle = "insights.card.depositBalance.title"
        static let expenseTitle = "insights.card.expense.title"
        static let goalProgressTitle = "insights.card.goalProgress.title"
        static let incomeTitle = "insights.card.income.title"
        static let incomeBreakdownTitle = "insights.chart.incomeBreakdown.title"
        static let netTitle = "insights.card.net.title"
        static let netSubtitle = "insights.card.net.subtitle"
        static let netWorthSubtitle = "insights.card.netWorth.subtitle"
        static let netWorthTitle = "insights.card.netWorth.title"
        static let insightsTitle = "insights.screen.title"
        static let itemSummaryFormat = "insights.item.summary.format"
        static let loanBalanceSubtitle = "insights.card.loanBalance.subtitle"
        static let loanBalanceTitle = "insights.card.loanBalance.title"
        static let matures = "insights.deposit.matures"
        static let month = "insights.filter.month"
        static let nextSectionSubtitle = "insights.section.next.subtitle"
        static let nextSectionTitle = "insights.section.next.title"
        static let nextSectionClearSubtitle = "insights.section.next.clearSubtitle"
        static let nextSectionClearTitle = "insights.section.next.clearTitle"
        static let nextDepositInterestTitle = "insights.card.nextDepositInterest.title"
        static let nextLoanPaymentTitle = "insights.card.nextLoanPayment.title"
        static let nextPayout = "insights.deposit.nextPayout"
        static let noActiveLoans = "insights.loan.noActiveLoans"
        static let noExpenseData = "insights.expense.noData"
        static let noGoalSet = "insights.goal.noGoalSet"
        static let noIncomeData = "insights.income.noData"
        static let noUpcomingPayment = "insights.loan.noUpcomingPayment"
        static let overviewSectionSubtitle = "insights.section.overview.subtitle"
        static let overviewSectionTitle = "insights.section.overview.title"
        static let pieModeExpense = "insights.pieMode.expense"
        static let pieModeIncome = "insights.pieMode.income"
        static let range = "insights.filter.range"
        static let barModeExpense = "insights.barMode.expense"
        static let barModeIncome = "insights.barMode.income"
        static let barModeNet = "insights.barMode.net"
        static let recurringExpenseTitle = "insights.card.recurringExpense.title"
        static let recurringIncomeTitle = "insights.card.recurringIncome.title"
        static let reviewMonthlySubtitle = "insights.review.monthly.subtitle"
        static let reviewMonthlyTitle = "insights.review.monthly.title"
        static let reviewPlaceholderBadge = "insights.review.placeholder.badge"
        static let reviewPlaceholderMessage = "insights.review.placeholder.message"
        static let reviewPlaceholderSubtitle = "insights.review.placeholder.subtitle"
        static let reviewSectionSubtitle = "insights.review.section.subtitle"
        static let reviewSectionTitle = "insights.review.section.title"
        static let reviewYearlySubtitle = "insights.review.yearly.subtitle"
        static let reviewYearlyTitle = "insights.review.yearly.title"
        static let resumeOrCreateGoal = "insights.goal.resumeOrCreate"
        static let savingsRateTitle = "insights.card.savingsRate.title"
        static let savingsRateSubtitle = "insights.card.savingsRate.subtitle"
        static let setGoalInSettings = "insights.goal.setInSettings"
        static let targetFormat = "insights.goal.target.format"
        static let topExpenseTitle = "insights.card.topExpense.title"
        static let topExpenseCategoryTitle = "insights.card.topExpenseCategory.title"
        static let topExpenseDrilldownHint = "insights.card.topExpense.drilldownHint"
        static let topIncomeTitle = "insights.card.topIncome.title"
        static let trendSectionSubtitle = "insights.section.trend.subtitle"
        static let trendSectionTitle = "insights.section.trend.title"
        static let trendUnavailableForCustomRangeSubtitle = "insights.section.trend.unavailable.subtitle"
        static let trendUnavailableForCustomRangeTitle = "insights.section.trend.unavailable.title"
        static let week = "insights.filter.week"
        static let year = "insights.filter.year"
    }

    enum Shared {
        static let expense = "shared.expense"
        static let income = "shared.income"
        static let incomeVsExpense = "shared.incomeVsExpense"
        static let net = "shared.net"
        static let noTrendDataForSelectedPeriod = "shared.noTrendDataForSelectedPeriod"
        static let trend = "shared.trend"
    }

    enum Onboarding {
        static let aSimpleAndIntelligentWay = "onboarding.welcome.subtitle"
        static let advancedSetupLater = "onboarding.quickStart.advancedLater"
        static let baseCurrency = "onboarding.baseCurrency"
        static let chooseLanguageAndCurrency = "onboarding.languageCurrency.subtitle"
        static let entrySelectionTitle = "onboarding.entry.title"
        static let entrySelectionSubtitle = "onboarding.entry.subtitle"
        static let enterAssetsAndDebt = "onboarding.startingPoint.subtitle"
        static let financialGoal = "onboarding.goal.title"
        static let goalTitle = "onboarding.goal.field.title"
        static let goalTitleOptional = "onboarding.goal.field.title.optional"
        static let importExistingRecordsTitle = "onboarding.entry.import.title"
        static let importExistingRecordsSubtitle = "onboarding.entry.import.subtitle"
        static let importPathIntroTitle = "onboarding.import.intro.title"
        static let importPathIntroSubtitle = "onboarding.import.intro.subtitle"
        static let ifNoGoalYet = "onboarding.goal.hint.skip"
        static let ifUnsureEnterZero = "onboarding.startingPoint.hint.zero"
        static let includeCurrentAssets = "onboarding.goal.includeAssets"
        static let languageAndCurrency = "onboarding.languageCurrency.title"
        static let myGoal = "onboarding.goal.defaultTitle"
        static let notificationsOptionalTitle = "onboarding.quickStart.notifications.title"
        static let notificationsOptionalSubtitle = "onboarding.quickStart.notifications.subtitle"
        static let quickStartTitle = "onboarding.entry.quickStart.title"
        static let quickStartSubtitle = "onboarding.entry.quickStart.subtitle"
        static let selectedFormat = "onboarding.selection.summary.format"
        static let setAnOptionalTarget = "onboarding.goal.subtitle"
        static let skip = "onboarding.action.skip"
        static let startFreshTitle = "onboarding.entry.startFresh.title"
        static let startFreshSubtitle = "onboarding.entry.startFresh.subtitle"
        static let startingPoint = "onboarding.startingPoint.title"
        static let targetAmount = "onboarding.goal.field.targetAmount"
        static let totalAssets = "onboarding.startingPoint.totalAssets"
        static let totalDebt = "onboarding.startingPoint.totalDebt"
        static let welcomeToFinTrack = "onboarding.welcome.title"
        static let actionImport = "onboarding.action.import"
        static let actionContinue = "onboarding.action.continue"
        static let importChooseCSVFile = "onboarding.import.chooseCSVFile"
        static let importFileParsedLocally = "onboarding.import.fileParsedLocally"
        static let importRequiredHeaders = "onboarding.import.requiredHeaders"
        static let importSelectCSVTitle = "onboarding.import.selectCSVTitle"
        static let importPreviewTitle = "onboarding.import.previewTitle"
        static let importPreviewSubtitle = "onboarding.import.previewSubtitle"
        static let importCategoriesToCreate = "onboarding.import.categoriesToCreate"
        static let importFirstParsedRows = "onboarding.import.firstParsedRows"
        static let importValidRows = "onboarding.import.validRows"
        static let importFatalErrors = "onboarding.import.fatalErrors"
        static let importNotAvailable = "onboarding.import.notAvailable"
        static let importCompletedTitle = "onboarding.import.completedTitle"
        static let importCompletedSubtitle = "onboarding.import.completedSubtitle"
        static let importRowsImported = "onboarding.import.rowsImported"
        static let importRowsSkipped = "onboarding.import.rowsSkipped"
        static let importDateRange = "onboarding.import.dateRange"
        static let importImportedDateRange = "onboarding.import.importedDateRange"
        static let importTotalIncome = "onboarding.import.totalIncome"
        static let importTotalExpense = "onboarding.import.totalExpense"
        static let importTotalIncomeImported = "onboarding.import.totalIncomeImported"
        static let importTotalExpenseImported = "onboarding.import.totalExpenseImported"
        static let importCategoriesCreated = "onboarding.import.categoriesCreated"
        static let importPossibleDuplicates = "onboarding.import.possibleDuplicates"
        static let importNoCSVSelected = "onboarding.import.noCSVSelected"
        static let importContractMismatch = "onboarding.import.contractMismatch"
        static let importWarningsReady = "onboarding.import.warningsReady"
        static let importReadyForPreview = "onboarding.import.readyForPreview"
        static let importFinishedContinue = "onboarding.import.finishedContinue"
        static let importFailedNoAdvance = "onboarding.import.failedNoAdvance"
    }

    enum App {
        static let insights = "app.tab.insights"
        static let record = "app.tab.record"
        static let settings = "app.tab.settings"
    }

    enum Loan {
        static let amortizationSchedule = "loan.amortizationSchedule"
        static let annualRate = "loan.annualRate"
        static let autoFilledDateFormat = "loan.autoFilledDateFormat"
        static let autoFilledFromLiveData = "loan.autoFilledFromLiveData"
        static let createLoan = "loan.createLoan"
        static let currency = "loan.currency"
        static let delete = "loan.delete"
        static let downPayment = "loan.downPayment"
        static let downPaymentInvalid = "loan.downPaymentInvalid"
        static let downPaymentPercent = "loan.downPaymentPercent"
        static let editLoan = "loan.editLoan"
        static let estimatedMonthlyPayment = "loan.estimatedMonthlyPayment"
        static let estimatedLastPayment = "loan.estimatedLastPayment"
        static let exchangeRate = "loan.exchangeRate"
        static let financed = "loan.financed"
        static let financedAmountFormat = "loan.financedAmountFormat"
        static let first = "loan.first"
        static let firstPayment = "loan.firstPayment"
        static let firstPaymentDate = "loan.firstPaymentDate"
        static let foreignCurrencyHint = "loan.foreignCurrencyHint"
        static let interest = "loan.interest"
        static let last = "loan.last"
        static let lastPayment = "loan.lastPayment"
        static let loadingRate = "loan.loadingRate"
        static let loanRecurringPaymentTitleFormat = "loan.loanRecurringPaymentTitleFormat"
        static let loanPaymentIndexFormat = "loan.loanPaymentIndexFormat"
        static let loanPrincipalComponentFormat = "loan.loanPrincipalComponentFormat"
        static let loanInterestComponentFormat = "loan.loanInterestComponentFormat"
        static let loanBalanceFormat = "loan.loanBalanceFormat"
        static let loanStartDateFormat = "loan.loanStartDateFormat"
        static let loanTermRateCategoryFormat = "loan.loanTermRateCategoryFormat"
        static let loans = "loan.loans"
        static let method = "loan.method"
        static let monthly = "loan.monthly"
        static let months = "loan.months"
        static let mortgage = "loan.mortgage"
        static let newLoan = "loan.newLoan"
        static let noLoansYet = "loan.noLoansYet"
        static let notes = "loan.notes"
        static let optionalNote = "loan.optionalNote"
        static let overview = "loan.overview"
        static let payments = "loan.payments"
        static let percentPresetFormat = "loan.percentPresetFormat"
        static let preview = "loan.preview"
        static let principal = "loan.principal"
        static let principalInterestNoteFormat = "loan.principalInterestNoteFormat"
        static let refreshingRate = "loan.refreshingRate"
        static let repayment = "loan.repayment"
        static let repaymentMethod = "loan.repaymentMethod"
        static let saveChanges = "loan.saveChanges"
        static let savedSnapshot = "loan.savedSnapshot"
        static let schedule = "loan.schedule"
        static let setTerm = "loan.setTerm"
        static let summary = "loan.summary"
        static let term = "loan.term"
        static let termMonthsFormat = "loan.termMonthsFormat"
        static let thisNoteWillBeCopied = "loan.thisNoteWillBeCopied"
        static let title = "loan.title"
        static let total = "loan.total"
        static let totalAmount = "loan.totalAmount"
        static let totalBreakdownFormat = "loan.totalBreakdownFormat"
        static let totalInterest = "loan.totalInterest"
        static let totalMinusDownPaymentHint = "loan.totalMinusDownPaymentHint"
        static let totalRepayment = "loan.totalRepayment"
        static let updateLoanHint = "loan.updateLoanHint"
        static let years = "loan.years"
        static let yr = "loan.yr"
        static let mo = "loan.mo"
    }

    enum LoanModel {
        static let decreasingMonthlyTotal = "Decreasing monthly total"
        static let emi = "EMI"
        static let epm = "EPM"
        static let fixedMonthlyTotal = "Fixed monthly total"
        static let interestOnlyPrincipalAtEnd = "Interest only, principal at end"
        static let io = "IO"
    }

    enum Deposit {
        static let active = "deposit.active"
        static let amount = "deposit.amount"
        static let annualInterestRate = "deposit.annualInterestRate"
        static let autoPredictionCustomisable = "deposit.autoPredictionCustomisable"
        static let carryover = "deposit.carryover"
        static let carryoverBreakdownFormat = "deposit.carryoverBreakdownFormat"
        static let closed = "deposit.closed"
        static let createDeposit = "deposit.createDeposit"
        static let currency = "deposit.currency"
        static let delete = "deposit.delete"
        static let deposits = "deposit.deposits"
        static let editDeposit = "deposit.editDeposit"
        static let expectedInterest = "deposit.expectedInterest"
        static let foreignCurrencyHint = "deposit.foreignCurrencyHint"
        static let interest = "deposit.interest"
        static let interestSetup = "deposit.interestSetup"
        static let interestSnapshotHint = "deposit.interestSnapshotHint"
        static let maturedDeposits = "deposit.maturedDeposits"
        static let maturity = "deposit.maturity"
        static let maturityDate = "deposit.maturityDate"
        static let maturityInterest = "deposit.maturityInterest"
        static let maturityInterestPayoutDescription = "deposit.maturityInterestPayoutDescription"
        static let maturityInterestRolloverDescription = "deposit.maturityInterestRolloverDescription"
        static let monthlyInterest = "deposit.monthlyInterest"
        static let name = "deposit.name"
        static let newDeposit = "deposit.newDeposit"
        static let noDepositsYet = "deposit.noDepositsYet"
        static let ok = "deposit.ok"
        static let optionalNote = "deposit.optionalNote"
        static let overview = "deposit.overview"
        static let preferences = "deposit.preferences"
        static let payout = "deposit.payout"
        static let rate = "deposit.rate"
        static let remindBefore = "deposit.remindBefore"
        static let reminder = "deposit.reminder"
        static let reminderTime = "deposit.reminderTime"
        static let rollover = "deposit.rollover"
        static let rolloverFrom = "deposit.rolloverFrom"
        static let rolloverSource = "deposit.rolloverSource"
        static let rolloverSourceHint = "deposit.rolloverSourceHint"
        static let sameDay = "deposit.sameDay"
        static let saveChanges = "deposit.saveChanges"
        static let settlement = "deposit.settlement"
        static let startDate = "deposit.startDate"
        static let timeline = "deposit.timeline"
        static let totalInterest = "deposit.totalInterest"
        static let unableToSaveDeposit = "deposit.unableToSaveDeposit"
        static let oneDayBefore = "deposit.oneDayBefore"
        static let threeDaysBefore = "deposit.threeDaysBefore"
        static let sevenDaysBefore = "deposit.sevenDaysBefore"
    }

    enum DepositModel {
        static let monthlyInterestNoRollover = "Interest is paid every month and does not roll into principal"
        static let monthlyCompoundingAtMaturity = "Interest accrues monthly, compounds into principal, and is settled at maturity"
        static let simpleInterestAtMaturity = "Interest is calculated without monthly compounding and paid once at maturity"
    }

    enum Recurring {
        static let active = "recurring.active"
        static let amount = "recurring.amount"
        static let cadence = "recurring.cadence"
        static let category = "recurring.category"
        static let createRule = "recurring.createRule"
        static let currency = "recurring.currency"
        static let customCategory = "recurring.customCategory"
        static let delete = "recurring.delete"
        static let editRecurring = "recurring.editRecurring"
        static let end = "recurring.end"
        static let endDate = "recurring.endDate"
        static let every = "recurring.every"
        static let everyIntervalFormat = "recurring.everyIntervalFormat"
        static let everyScheduleFormat = "recurring.everyScheduleFormat"
        static let expense = "recurring.expense"
        static let foreignCurrencyHint = "recurring.foreignCurrencyHint"
        static let hasEndDate = "recurring.hasEndDate"
        static let income = "recurring.income"
        static let interval = "recurring.interval"
        static let newRecurring = "recurring.newRecurring"
        static let next = "recurring.next"
        static let nextExecution = "recurring.nextExecution"
        static let noEndDate = "recurring.noEndDate"
        static let noRecurringTransactionsYet = "recurring.noRecurringTransactionsYet"
        static let notes = "recurring.notes"
        static let ok = "recurring.ok"
        static let optionalNote = "recurring.optionalNote"
        static let overview = "recurring.overview"
        static let paused = "recurring.paused"
        static let recurring = "recurring.recurring"
        static let recurringHint = "recurring.recurringHint"
        static let remindBefore = "recurring.remindBefore"
        static let reminder = "recurring.reminder"
        static let reminderTime = "recurring.reminderTime"
        static let sameDay = "recurring.sameDay"
        static let saveChanges = "recurring.saveChanges"
        static let schedule = "recurring.schedule"
        static let title = "recurring.title"
        static let type = "recurring.type"
        static let unableToSaveRule = "recurring.unableToSaveRule"
        static let oneDayBefore = "recurring.oneDayBefore"
    }

    enum Transaction {
        static let amount = "transaction.editor.amount.section"
        static let autoRate = "transaction.editor.exchangeRate.autoRate"
        static let baseAmount = "transaction.detail.baseAmount"
        static let baseCurrency = "transaction.detail.baseCurrency"
        static let categoryMatchedRecordsFormat = "transaction.search.categoryMatchedRecords.format"
        static let categoryMatches = "transaction.search.categoryMatches.title"
        static let date = "transaction.editor.date.section"
        static let deleteTransaction = "transaction.detail.delete.action"
        static let deleteTransactionPrompt = "transaction.detail.delete.prompt"
        static let details = "transaction.detail.section.details"
        static let editTransaction = "transaction.detail.edit.action"
        static let exchangeRateAutoFilledFormat = "transaction.exchangeRate.autoFilled.format"
        static let exchangeRateAutoFilledLive = "transaction.exchangeRate.autoFilled.live"
        static let exchangeRateLoading = "transaction.exchangeRate.loading"
        static let exchangeRateRefreshing = "transaction.exchangeRate.refreshing"
        static let exchangeRateSavedSnapshot = "transaction.exchangeRate.savedSnapshot"
        static let exchangeRate = "transaction.exchangeRate.title"
        static let expenseAmountFormat = "transaction.summary.expenseAmount.format"
        static let incomeAmountFormat = "transaction.summary.incomeAmount.format"
        static let keywordAppearsInRecordsFormat = "transaction.search.keywordAppearsInRecords.format"
        static let note = "transaction.note.section"
        static let noteMatches = "transaction.search.noteMatches.title"
        static let noMatchingRecords = "transaction.search.noMatchingRecords"
        static let originalAmount = "transaction.detail.originalAmount"
        static let originalCurrency = "transaction.detail.originalCurrency"
        static let results = "transaction.search.results.title"
        static let search = "transaction.search.screen.title"
        static let searchCategoryOrNote = "transaction.search.field.placeholder"
        static let sameAsBaseCurrency = "transaction.detail.sameAsBaseCurrency"
        static let totalRecordsFormat = "transaction.search.totalRecords.format"
        static let totalAmount = "transaction.search.totalAmount.label"
        static let thisActionCannotBeUndone = "transaction.delete.cannotUndo"
        static let transaction = "transaction.detail.screen.title"
        static let transactionDate = "transaction.editor.transactionDate"
        static let type = "transaction.type.label"
    }

    enum Record {
        static let deposits = "record.tools.deposits.title"
        static let depositsSubtitle = "record.tools.deposits.subtitle"
        static let loanPayment = "record.loanPayment.badge"
        static let loans = "record.tools.loans.title"
        static let loansSubtitle = "record.tools.loans.subtitle"
        static let more = "record.tools.screen.title"
        static let noTransactionsYet = "record.recent.empty.title"
        static let quickRecord = "record.quickRecord.title"
        static let recent = "record.recent.screen.title"
        static let record = "record.screen.title"
        static let recurring = "record.tools.recurring.title"
        static let recurringSubtitle = "record.tools.recurring.subtitle"
        static let recordHistoryHint = "record.recent.empty.message"
        static let searchCategory = "record.search.category.title"
        static let searchEnd = "record.search.range.end"
        static let searchStart = "record.search.range.start"
        static let todaySpend = "record.todaySpend.title"
    }

    enum Manager {
        static let autoGenerated = "Auto-generated"
        static let depositInterest = "Deposit interest"
        static let depositMatured = "Deposit matured"
        static let depositMaturedRollover = "Deposit matured (rollover)"
        static let myFinTrack = "My FinTrack"
        static let prefixNameFormat = "%@: %@"
        static let prefixNameNoteFormat = "%@: %@ • %@"
        static let rolloverDetailFormat = "Rolled into %@: principal %@, interest %@"
    }

    enum Currency {
        static let base = "Base"
        static let baseCurrency = "Base Currency"
        static let commonCurrencies = "Common Currencies"
        static let commonCurrency = "Common Currency"
        static let currencies = "Currencies"
        static let currency = "Currency"
        static let onlyBaseAndCommonAppear = "Only base currency and selected common currencies will appear in currency pickers."
        static let searchCurrency = "Search currency"
        static let selectedCurrencyAddedAutomatically = "Selected currency will be added to Common Currencies automatically."
        static let unableToChangeBaseCurrency = "Unable to Change Base Currency"
        static let updatingHistoricalExchangeSnapshots = "Updating historical exchange snapshots…"
    }

    enum Notification {
        static let authorization = "notification.authorization"
        static let denied = "notification.denied"
        static let depositMaturesInDaysExpectedInterestFormat = "notification.depositMaturesInDaysExpectedInterest.format"
        static let depositMaturesTodayExpectedInterestFormat = "notification.depositMaturesTodayExpectedInterest.format"
        static let ephemeral = "notification.ephemeral"
        static let finTrackCanDeliverLocalReminderNotificationsNormally = "notification.delivery.normal"
        static let finTrackCanSendNotificationsQuietlyWithProvisionalAuthorization = "notification.delivery.provisional"
        static let finTrackCurrentlyHasTemporaryNotificationAuthorization = "notification.authorization.temporary"
        static let ifNotificationsDenied = "notification.denied.hint"
        static let info = "notification.info"
        static let notDetermined = "notification.notDetermined"
        static let notificationAuthorizationStatusCouldNotBeDetermined = "notification.status.unknown"
        static let notificationPermissionHasNotBeenRequestedYet = "notification.permission.notRequested"
        static let notificationsAreCurrentlyTurnedOffForFinTrackEnableThemInTheIPhoneSettingsAppToReceiveReminders = "notification.disabled.systemHint"
        static let notifications = "notification.notifications"
        static let openSystemSettings = "notification.openSystemSettings"
        static let provisional = "notification.provisional"
        static let recurringAndDepositReminders = "notification.reminders.summary"
        static let recurringReminderFormat = "notification.recurringReminder.format"
        static let refreshStatus = "notification.refreshStatus"
        static let requestPermission = "notification.requestPermission"
        static let status = "notification.status"
        static let unknown = "notification.unknown"
        static let upcomingRecurringInDaysFormat = "notification.upcomingRecurringInDays.format"
        static let authorized = "notification.authorized"
    }

    enum Keyboard {
        static let clear = "keyboard.clear"
    }

    enum SettingsCommon {
        static let about = "settings.common.about"
        static let account = "settings.common.account"
        static let balance = "settings.common.balance"
        static let app = "settings.common.app"
        static let accomplished = "settings.common.accomplished"
        static let assets = "settings.common.assets"
        static let categories = "settings.common.categories"
        static let currency = "settings.common.currency"
        static let data = "settings.common.data"
        static let dateFormat = "settings.common.dateFormat"
        static let debt = "settings.common.debt"
        static let delete = "settings.common.delete"
        static let deleteGoal = "settings.common.deleteGoal"
        static let edit = "settings.common.edit"
        static let export = "settings.common.export"
        static let finance = "settings.common.finance"
        static let followSystemTheme = "settings.common.followSystemTheme"
        static let goal = "settings.common.goal"
        static let info = "settings.common.info"
        static let keyboardHaptics = "settings.common.keyboardHaptics"
        static let darkMode = "settings.common.darkMode"
        static let netWorth = "settings.common.netWorth"
        static let notifications = "settings.common.notifications"
        static let pause = "settings.common.pause"
        static let preferences = "settings.common.preferences"
        static let privacyAndData = "settings.common.privacyAndData"
        static let progress = "settings.common.progress"
        static let reset = "settings.common.reset"
        static let save = "settings.common.save"
        static let saveChanges = "settings.common.saveChanges"
        static let startDate = "settings.common.startDate"
        static let title = "settings.common.title"
        static let type = "settings.common.type"
        static let summary = "settings.common.summary"
        static let support = "settings.common.support"
        static let targetAmount = "settings.common.targetAmount"
        static let undo = "settings.common.undo"
        static let version = "settings.common.version"
    }

    enum SettingsAbout {
        static let faq = "settings.about.faq"
        static let privacy = "settings.about.privacy"
    }

    enum SettingsSupport {
        static let commonQuestionsAboutDataAndSync = "settings.support.commonQuestionsAboutDataAndSync"
        static let contact = "settings.support.contact"
        static let contactSupport = "settings.support.contactSupport"
        static let emailSupportAndProblemReports = "settings.support.emailSupportAndProblemReports"
        static let emailSupport = "settings.support.emailSupport"
        static let howYourDataIsStoredAndProtected = "settings.support.howYourDataIsStoredAndProtected"
        static let usePreferredSupportEmail = "settings.support.usePreferredSupportEmail"
        static let reportAProblem = "settings.support.reportAProblem"
        static let describeBugSyncUnexpected = "settings.support.describeBugSyncUnexpected"
        static let needHelpOrReportProblem = "settings.support.needHelpOrReportProblem"
        static let supportCenterIntro = "settings.support.supportCenterIntro"
        static let contactIntro = "settings.support.contactIntro"
        static let note = "settings.support.note"
        static let options = "settings.support.options"
        static let support = "settings.support.support"
        static let supportCenterNote = "settings.support.supportCenterNote"
        static let contactNote = "settings.support.contactNote"
        static let privacyCorePrinciple = "settings.support.privacyCorePrinciple"
        static let privacyLocalStorage = "settings.support.privacyLocalStorage"
        static let privacyICloud = "settings.support.privacyICloud"
        static let privacyNoTracking = "settings.support.privacyNoTracking"
        static let privacySummaryOnDevice = "settings.support.privacySummaryOnDevice"
        static let privacySummaryNoAccess = "settings.support.privacySummaryNoAccess"
        static let privacySummaryAppleICloud = "settings.support.privacySummaryAppleICloud"
        static let privacySummaryNoCollection = "settings.support.privacySummaryNoCollection"
        static let faqWhereIsDataStored = "settings.support.faqWhereIsDataStored"
        static let faqWhereIsDataStoredAnswer = "settings.support.faqWhereIsDataStoredAnswer"
        static let faqCollectFinancialInfo = "settings.support.faqCollectFinancialInfo"
        static let faqCollectFinancialInfoAnswer = "settings.support.faqCollectFinancialInfoAnswer"
        static let faqHowICloudSyncWorks = "settings.support.faqHowICloudSyncWorks"
        static let faqHowICloudSyncWorksAnswer = "settings.support.faqHowICloudSyncWorksAnswer"
        static let faqDeleteApp = "settings.support.faqDeleteApp"
        static let faqDeleteAppAnswer = "settings.support.faqDeleteAppAnswer"
    }

    enum SettingsData {
        static let deleteAllData = "settings.data.deleteAllData"
        static let deleteAllDataPrompt = "settings.data.deleteAllDataPrompt"
        static let exportData = "settings.data.exportData"
        static let importData = "settings.data.importData"
        static let importNow = "settings.data.importNow"
        static let importEntryPointDescription = "settings.data.importEntryPointDescription"
        static let importContractMismatch = "settings.data.importContractMismatch"
        static let importWarningsReady = "settings.data.importWarningsReady"
        static let importReady = "settings.data.importReady"
        static let importFinished = "settings.data.importFinished"
        static let importFailed = "settings.data.importFailed"
        static let noCSVSelected = "settings.data.noCSVSelected"
        static let recurringRules = "settings.data.recurringRules"
        static let thisActionCannotBeUndone = "settings.data.actionCannotBeUndone"
        static let transactions = "settings.data.transactions"
    }

    enum SettingsFinance {
        static let accomplishedGoals = "settings.finance.accomplishedGoals"
        static let currentFinancialProfile = "settings.finance.currentFinancialProfile"
        static let currentGoals = "settings.finance.currentGoals"
        static let currentGoalAccomplished = "settings.finance.currentGoalAccomplished"
        static let currentGoalPaused = "settings.finance.currentGoalPaused"
        static let editGoal = "settings.finance.editGoal"
        static let editSection = "settings.finance.editSection"
        static let financialGoal = "settings.finance.financialGoal"
        static let financialProfile = "settings.finance.financialProfile"
        static let goalTitle = "settings.finance.goalTitle"
        static let currentNetWorth = "settings.finance.currentNetWorth"
        static let includeCurrentAssets = "settings.finance.includeCurrentAssets"
        static let myGoal = "settings.finance.myGoal"
        static let noGoalSet = "settings.finance.noGoalSet"
        static let profile = "settings.finance.profile"
        static let progressPercentFormat = "settings.finance.progressPercentFormat"
        static let saveGoal = "settings.finance.saveGoal"
        static let setYourGoal = "settings.finance.setYourGoal"
        static let targetFormat = "settings.finance.targetFormat"
        static let assetsFormat = "settings.finance.assetsFormat"
        static let availableAssets = "settings.finance.availableAssets"
        static let debtFormat = "settings.finance.debtFormat"
        static let depositPrincipal = "settings.finance.depositPrincipal"
        static let loansFormat = "settings.finance.loansFormat"
        static let goalCountFormat = "settings.finance.goalCountFormat"
        static let categoryManagement = "settings.finance.categoryManagement"
        static let categoryManagementSubtitle = "settings.finance.categoryManagementSubtitle"
    }

    enum Export {
        static let sharingUnavailable = "export.sharingUnavailable"
    }

    enum SettingsAccount {
        static let account = "settings.account.account"
        static let accountName = "settings.account.accountName"
        static let accounts = "settings.account.accounts"
        static let addAccount = "settings.account.addAccount"
        static let cancel = "settings.account.cancel"
        static let deleteAccountAndResetApp = "settings.account.deleteAccountAndResetApp"
        static let deleteAccountAndResetAppPrompt = "settings.account.deleteAccountAndResetAppPrompt"
        static let existingAccounts = "settings.account.existingAccounts"
        static let finTrackAccount = "settings.account.finTrackAccount"
        static let noAccountsYet = "settings.account.noAccountsYet"
        static let notebookName = "settings.account.notebookName"
        static let openICloudSync = "settings.account.openICloudSync"
        static let placeholderDescription = "settings.account.placeholderDescription"
        static let placeholderTitle = "settings.account.placeholderTitle"
        static let saveAccount = "settings.account.saveAccount"
        static let saveNotebookName = "settings.account.saveNotebookName"
        static let settings = "settings.account.settings"
        static let signInWithApple = "settings.account.signInWithApple"
        static let signInRequiredForICloud = "settings.account.signInRequiredForICloud"
        static let signOut = "settings.account.signOut"
        static let signOutKeepsLocalData = "settings.account.signOutKeepsLocalData"
        static let signOutPrompt = "settings.account.signOutPrompt"
        static let signOutUnavailableUntilSignIn = "settings.account.signOutUnavailableUntilSignIn"
        static let signedInWithApple = "settings.account.signedInWithApple"
        static let status = "settings.account.status"
        static let deleteAccountResetWarning = "settings.account.deleteAccountResetWarning"
        static let deleteLocalDataAndResetApp = "settings.account.deleteLocalDataAndResetApp"
        static let deleteLocalDataAndResetAppSubtitle = "settings.account.deleteLocalDataAndResetAppSubtitle"
        static let deleteLocalDataAndResetAppAlert = "settings.account.deleteLocalDataAndResetAppAlert"
        static let localOnlyStorageDescription = "settings.account.localOnlyStorageDescription"
        static let storageMode = "settings.account.storageMode"
        static let local = "settings.account.local"
        static let importExport = "settings.account.importExport"
        static let localOnly = "settings.account.localOnly"
        static let continueSetup = "settings.account.continueSetup"
        static let continueSetupPending = "settings.account.continueSetupPending"
        static let continueSetupOptional = "settings.account.continueSetupOptional"
        static let continueSetupEnabled = "settings.account.continueSetupEnabled"
        static let continueSetupIntro = "settings.account.continueSetupIntro"
        static let continueSetupProgressFormat = "settings.account.continueSetupProgressFormat"
        static let continueSetupFinancialBaseline = "settings.account.continueSetupFinancialBaseline"
        static let continueSetupFinancialBaselineEmpty = "settings.account.continueSetupFinancialBaselineEmpty"
        static let continueSetupFinancialBaselineConfigured = "settings.account.continueSetupFinancialBaselineConfigured"
        static let continueSetupFinancialGoal = "settings.account.continueSetupFinancialGoal"
        static let continueSetupFinancialGoalEmpty = "settings.account.continueSetupFinancialGoalEmpty"
        static let continueSetupFinancialGoalConfigured = "settings.account.continueSetupFinancialGoalConfigured"
        static let continueSetupHistoricalRecords = "settings.account.continueSetupHistoricalRecords"
        static let continueSetupHistoricalRecordsEmpty = "settings.account.continueSetupHistoricalRecordsEmpty"
        static let continueSetupHistoricalRecordsConfigured = "settings.account.continueSetupHistoricalRecordsConfigured"
        static let continueSetupReminders = "settings.account.continueSetupReminders"
        static let continueSetupRemindersSubtitle = "settings.account.continueSetupRemindersSubtitle"
    }

    enum Profile {
        static let exportResetSummary = "profile.exportResetSummary"
        static let goalOff = "profile.goalOff"
        static let goalOn = "profile.goalOn"
        static let notSignedIn = "profile.notSignedIn"
        static let profileOff = "profile.profileOff"
        static let profileOn = "profile.profileOn"
        static let signedIn = "profile.signedIn"
        static let syncOff = "profile.syncOff"
        static let syncOn = "profile.syncOn"
        static let version = "profile.version"
    }
}

enum UIStringCatalogKeyResolver {
    static func resolve(_ key: String) -> String {
        switch key {
        // Common
        case UIStringKey.Common.add:
            return "Add"
        case UIStringKey.Common.all:
            return "All"
        case UIStringKey.Common.back:
            return "Back"
        case UIStringKey.Common.bank:
            return "Bank"
        case UIStringKey.Common.category:
            return "Category"
        case UIStringKey.Common.cash:
            return "Cash"
        case UIStringKey.Common.configured:
            return "Configured"
        case UIStringKey.Common.copy:
            return "Copy"
        case UIStringKey.Common.creditCard:
            return "Credit Card"
        case UIStringKey.Common.custom:
            return "Custom"
        case UIStringKey.Common.customCategory:
            return "Custom category"
        case UIStringKey.Common.day:
            return "Day"
        case UIStringKey.Common.delete:
            return "Delete"
        case UIStringKey.Common.done:
            return "Done"
        case UIStringKey.Common.expense:
            return "Expense"
        case UIStringKey.Common.finish:
            return "Finish"
        case UIStringKey.Common.income:
            return "Income"
        case UIStringKey.Common.investment:
            return "Investment"
        case UIStringKey.Common.language:
            return "Language"
        case UIStringKey.Common.month:
            return "Month"
        case UIStringKey.Common.noData:
            return "No data"
        case UIStringKey.Common.next:
            return "Next"
        case UIStringKey.Common.none:
            return "None"
        case UIStringKey.Common.notSet:
            return "Not set"
        case UIStringKey.Common.ok:
            return "OK"
        case UIStringKey.Common.other:
            return "Other"
        case UIStringKey.Common.warnings:
            return "Warnings"
        case UIStringKey.Common.week:
            return "Week"
        case UIStringKey.Common.year:
            return "Year"
        case UIStringKey.Common.pairSummaryFormat:
            return "%@ · %@"
        case UIStringKey.Common.tripleSummaryFormat:
            return "%@ · %@ · %@"

        // Shared
        case UIStringKey.Shared.expense:
            return "Expense"
        case UIStringKey.Shared.income:
            return "Income"
        case UIStringKey.Shared.incomeVsExpense:
            return "Income vs Expense"
        case UIStringKey.Shared.net:
            return "Net"
        case UIStringKey.Shared.noTrendDataForSelectedPeriod:
            return "No trend data for the selected period"
        case UIStringKey.Shared.trend:
            return "Trend"

        // Category
        case UIStringKey.Category.bonus:
            return "Bonus"
        case UIStringKey.Category.deposit:
            return "Deposit"
        case UIStringKey.Category.dining:
            return "Dining"
        case UIStringKey.Category.expenseCategories:
            return "Expense Categories"
        case UIStringKey.Category.gift:
            return "Gift"
        case UIStringKey.Category.health:
            return "Health"
        case UIStringKey.Category.incomeCategories:
            return "Income Categories"
        case UIStringKey.Category.investment:
            return "Investment"
        case UIStringKey.Category.loan:
            return "Loan"
        case UIStringKey.Category.manageCategories:
            return "Manage Categories"
        case UIStringKey.Category.merge:
            return "Merge"
        case UIStringKey.Category.mergeCategories:
            return "Merge Categories"
        case UIStringKey.Category.mergeCategoriesPromptFormat:
            return "A category named \"%@\" already exists. Merge all data from \"%@\" into it?"
        case UIStringKey.Category.newExpenseCategory:
            return "New expense category"
        case UIStringKey.Category.newIncomeCategory:
            return "New income category"
        case UIStringKey.Category.other:
            return "Other"
        case UIStringKey.Category.salary:
            return "Salary"
        case UIStringKey.Category.shopping:
            return "Shopping"
        case UIStringKey.Category.supermarket:
            return "Supermarket"
        case UIStringKey.Category.transport:
            return "Transport"
        case UIStringKey.Category.travel:
            return "Travel"

        // Onboarding
        case UIStringKey.Onboarding.aSimpleAndIntelligentWay:
            return "A simple and intelligent way to track your finances."
        case UIStringKey.Onboarding.advancedSetupLater:
            return "You can finish advanced setup later in Settings and tools."
        case UIStringKey.Onboarding.baseCurrency:
            return "Base Currency"
        case UIStringKey.Onboarding.chooseLanguageAndCurrency:
            return "Choose your preferred language and base currency for FinTrack."
        case UIStringKey.Onboarding.entrySelectionTitle:
            return "How do you want to begin?"
        case UIStringKey.Onboarding.entrySelectionSubtitle:
            return "Choose the setup path that best matches what you want to do first."
        case UIStringKey.Onboarding.enterAssetsAndDebt:
            return "Enter your current assets and debt to set a starting point for FinTrack."
        case UIStringKey.Onboarding.financialGoal:
            return "Financial Goal"
        case UIStringKey.Onboarding.goalTitle:
            return "Goal Title"
        case UIStringKey.Onboarding.goalTitleOptional:
            return "Goal Title (optional)"
        case UIStringKey.Onboarding.importExistingRecordsTitle:
            return "Import Existing Records"
        case UIStringKey.Onboarding.importExistingRecordsSubtitle:
            return "Bring in historical records from a CSV file."
        case UIStringKey.Onboarding.importPathIntroTitle:
            return "Import path selected"
        case UIStringKey.Onboarding.importPathIntroSubtitle:
            return "CSV import screens will be added next. For now, your onboarding route and basic setup choices are kept separate so this path can be completed cleanly in the next steps."
        case UIStringKey.Onboarding.ifNoGoalYet:
            return "If you do not have a financial goal yet, tap Skip in the top-right corner. You can always add one later in Settings."
        case UIStringKey.Onboarding.ifUnsureEnterZero:
            return "If you’re not sure, enter 0 and update it later in Settings."
        case UIStringKey.Onboarding.includeCurrentAssets:
            return "Include Current Assets"
        case UIStringKey.Onboarding.languageAndCurrency:
            return "Language & Currency"
        case UIStringKey.Onboarding.myGoal:
            return "My Goal"
        case UIStringKey.Onboarding.notificationsOptionalTitle:
            return "Notifications are optional"
        case UIStringKey.Onboarding.notificationsOptionalSubtitle:
            return "Enable reminders now if you want FinTrack to surface recurring and maturity alerts. You can also skip and turn this on later."
        case UIStringKey.Onboarding.quickStartTitle:
            return "Quick Start"
        case UIStringKey.Onboarding.quickStartSubtitle:
            return "Start recording right away with minimal setup."
        case UIStringKey.Onboarding.selectedFormat:
            return "Selected: %@ · %@"
        case UIStringKey.Onboarding.setAnOptionalTarget:
            return "Set an optional target now, or skip this step and add one later."
        case UIStringKey.Onboarding.skip:
            return "Skip"
        case UIStringKey.Onboarding.startFreshTitle:
            return "Start Fresh"
        case UIStringKey.Onboarding.startFreshSubtitle:
            return "Set up your current financial starting point."
        case UIStringKey.Onboarding.startingPoint:
            return "Starting Point"
        case UIStringKey.Onboarding.targetAmount:
            return "Target Amount"
        case UIStringKey.Onboarding.totalAssets:
            return "Total Assets"
        case UIStringKey.Onboarding.totalDebt:
            return "Total Debt"
        case UIStringKey.Onboarding.welcomeToFinTrack:
            return "Welcome to FinTrack"
        case UIStringKey.Onboarding.actionImport:
            return "Import"
        case UIStringKey.Onboarding.actionContinue:
            return "Continue"
        case UIStringKey.Onboarding.importChooseCSVFile:
            return "Choose CSV File"
        case UIStringKey.Onboarding.importFileParsedLocally:
            return "The file is parsed locally. Review the preview before anything is imported."
        case UIStringKey.Onboarding.importRequiredHeaders:
            return "Required headers: date, type, amount, category. Optional headers: note, currency, account, exchange_rate."
        case UIStringKey.Onboarding.importSelectCSVTitle:
            return "Select Your CSV"
        case UIStringKey.Onboarding.importPreviewTitle:
            return "Import Preview"
        case UIStringKey.Onboarding.importPreviewSubtitle:
            return "Review how FinTrack will interpret the first rows before anything is written."
        case UIStringKey.Onboarding.importCategoriesToCreate:
            return "Categories To Create"
        case UIStringKey.Onboarding.importFirstParsedRows:
            return "First Parsed Rows"
        case UIStringKey.Onboarding.importValidRows:
            return "Valid Rows"
        case UIStringKey.Onboarding.importFatalErrors:
            return "Fatal Errors"
        case UIStringKey.Onboarding.importNotAvailable:
            return "Not available"
        case UIStringKey.Onboarding.importCompletedTitle:
            return "Import Completed"
        case UIStringKey.Onboarding.importCompletedSubtitle:
            return "Historical records are in. You can continue with present-day baseline setup next."
        case UIStringKey.Onboarding.importRowsImported:
            return "Rows Imported"
        case UIStringKey.Onboarding.importRowsSkipped:
            return "Rows Skipped"
        case UIStringKey.Onboarding.importDateRange:
            return "Date Range"
        case UIStringKey.Onboarding.importImportedDateRange:
            return "Imported Date Range"
        case UIStringKey.Onboarding.importTotalIncome:
            return "Total Income"
        case UIStringKey.Onboarding.importTotalExpense:
            return "Total Expense"
        case UIStringKey.Onboarding.importTotalIncomeImported:
            return "Total Income Imported"
        case UIStringKey.Onboarding.importTotalExpenseImported:
            return "Total Expense Imported"
        case UIStringKey.Onboarding.importCategoriesCreated:
            return "Categories Created"
        case UIStringKey.Onboarding.importPossibleDuplicates:
            return "Possible Duplicates"
        case UIStringKey.Onboarding.importNoCSVSelected:
            return "No CSV file was selected."
        case UIStringKey.Onboarding.importContractMismatch:
            return "This file does not fully match the current standard CSV contract. Review the preview for exact issues."
        case UIStringKey.Onboarding.importWarningsReady:
            return "The file is ready, but some rows include warnings that you should review before import."
        case UIStringKey.Onboarding.importReadyForPreview:
            return "The file matches the current CSV contract and is ready for preview."
        case UIStringKey.Onboarding.importFinishedContinue:
            return "Import finished. Review the summary, then continue with current-state setup."
        case UIStringKey.Onboarding.importFailedNoAdvance:
            return "Import failed before completion. No onboarding state was advanced."

        // SettingsCommon
        case UIStringKey.SettingsCommon.about:
            return "About"
        case UIStringKey.SettingsCommon.account:
            return "Account"
        case UIStringKey.SettingsCommon.balance:
            return "Balance"
        case UIStringKey.SettingsCommon.app:
            return "App"
        case UIStringKey.SettingsCommon.accomplished:
            return "Accomplished"
        case UIStringKey.SettingsCommon.assets:
            return "Assets"
        case UIStringKey.SettingsCommon.categories:
            return "Categories"
        case UIStringKey.SettingsCommon.currency:
            return "Currency"
        case UIStringKey.SettingsCommon.data:
            return "Data"
        case UIStringKey.SettingsCommon.dateFormat:
            return "Date Format"
        case UIStringKey.SettingsCommon.debt:
            return "Debt"
        case UIStringKey.SettingsCommon.delete:
            return "Delete"
        case UIStringKey.SettingsCommon.deleteGoal:
            return "Delete Goal"
        case UIStringKey.SettingsCommon.edit:
            return "Edit"
        case UIStringKey.SettingsCommon.export:
            return "Export"
        case UIStringKey.SettingsCommon.finance:
            return "Finance"
        case UIStringKey.SettingsCommon.goal:
            return "Goal"
        case UIStringKey.SettingsCommon.info:
            return "Info"
        case UIStringKey.SettingsCommon.keyboardHaptics:
            return "Keyboard Haptics"
        case UIStringKey.SettingsCommon.followSystemTheme:
            return "Follow System Theme"
        case UIStringKey.SettingsCommon.darkMode:
            return "Dark Mode"
        case UIStringKey.SettingsCommon.netWorth:
            return "Net Worth"
        case UIStringKey.SettingsCommon.notifications:
            return "Notifications"
        case UIStringKey.SettingsCommon.pause:
            return "Pause"
        case UIStringKey.SettingsCommon.preferences:
            return "Preferences"
        case UIStringKey.SettingsCommon.privacyAndData:
            return "Privacy & Data"
        case UIStringKey.SettingsCommon.progress:
            return "Progress"
        case UIStringKey.SettingsCommon.reset:
            return "Reset"
        case UIStringKey.SettingsCommon.save:
            return "Save"
        case UIStringKey.SettingsCommon.saveChanges:
            return "Save Changes"
        case UIStringKey.SettingsCommon.startDate:
            return "Start Date"
        case UIStringKey.SettingsCommon.title:
            return "Title"
        case UIStringKey.SettingsCommon.type:
            return "Type"
        case UIStringKey.SettingsCommon.summary:
            return "Summary"
        case UIStringKey.SettingsCommon.support:
            return "Support"
        case UIStringKey.SettingsCommon.targetAmount:
            return "Target Amount"
        case UIStringKey.SettingsCommon.undo:
            return "Undo"
        case UIStringKey.SettingsCommon.version:
            return "Version"

        // SettingsAbout
        case UIStringKey.SettingsAbout.faq:
            return "FAQ"
        case UIStringKey.SettingsAbout.privacy:
            return "Privacy"

        // SettingsSupport
        case UIStringKey.SettingsSupport.commonQuestionsAboutDataAndSync:
            return "Common questions about data and sync"
        case UIStringKey.SettingsSupport.contact:
            return "Contact"
        case UIStringKey.SettingsSupport.contactSupport:
            return "Contact Support"
        case UIStringKey.SettingsSupport.emailSupportAndProblemReports:
            return "Email support and problem reports"
        case UIStringKey.SettingsSupport.emailSupport:
            return "Email Support"
        case UIStringKey.SettingsSupport.howYourDataIsStoredAndProtected:
            return "How your data is stored and protected"
        case UIStringKey.SettingsSupport.usePreferredSupportEmail:
            return "Use your preferred support email address here"
        case UIStringKey.SettingsSupport.reportAProblem:
            return "Report a Problem"
        case UIStringKey.SettingsSupport.describeBugSyncUnexpected:
            return "Describe a bug, sync issue, or unexpected behavior"
        case UIStringKey.SettingsSupport.needHelpOrReportProblem:
            return "Need help or want to report a problem?"
        case UIStringKey.SettingsSupport.supportCenterIntro:
            return "Use this page as the main entry for future support channels and feedback options."
        case UIStringKey.SettingsSupport.contactIntro:
            return "You can use this page as the main support entry for feedback, bug reports, and future contact options."
        case UIStringKey.SettingsSupport.note:
            return "Note"
        case UIStringKey.SettingsSupport.options:
            return "Options"
        case UIStringKey.SettingsSupport.support:
            return "Support"
        case UIStringKey.SettingsSupport.supportCenterNote:
            return "Use FAQ, Contact Support, or Privacy & Data to learn more or report issues."
        case UIStringKey.SettingsSupport.contactNote:
            return "This page is ready for future email links, feedback forms, or help-center integrations."
        case UIStringKey.SettingsSupport.privacyCorePrinciple:
            return "FinTrack is designed with privacy as a core principle."
        case UIStringKey.SettingsSupport.privacyLocalStorage:
            return "All financial records and personal data entered in the app are stored locally on your device. The developer does not collect, store, or have access to your financial information."
        case UIStringKey.SettingsSupport.privacyICloud:
            return "If you choose to enable iCloud Sync, your data is synchronized using Apple’s iCloud services under your Apple ID. This process is handled by Apple’s infrastructure, and the developer does not have access to your synced data."
        case UIStringKey.SettingsSupport.privacyNoTracking:
            return "FinTrack does not include advertising SDKs, analytics trackers, or third-party systems that collect personal financial data."
        case UIStringKey.SettingsSupport.privacySummaryOnDevice:
            return "Your records stay on your device"
        case UIStringKey.SettingsSupport.privacySummaryNoAccess:
            return "The developer cannot access your financial data"
        case UIStringKey.SettingsSupport.privacySummaryAppleICloud:
            return "iCloud Sync is handled by Apple"
        case UIStringKey.SettingsSupport.privacySummaryNoCollection:
            return "No personal financial data is collected"
        case UIStringKey.SettingsSupport.faqWhereIsDataStored:
            return "Where is my data stored?"
        case UIStringKey.SettingsSupport.faqWhereIsDataStoredAnswer:
            return "All records are stored locally on your device."
        case UIStringKey.SettingsSupport.faqCollectFinancialInfo:
            return "Does FinTrack collect my financial information?"
        case UIStringKey.SettingsSupport.faqCollectFinancialInfoAnswer:
            return "No. FinTrack does not collect, store, or access your financial records."
        case UIStringKey.SettingsSupport.faqHowICloudSyncWorks:
            return "How does iCloud Sync work?"
        case UIStringKey.SettingsSupport.faqHowICloudSyncWorksAnswer:
            return "If enabled, synchronization is handled through Apple’s iCloud services under your Apple ID. The developer does not have access to this data."
        case UIStringKey.SettingsSupport.faqDeleteApp:
            return "What happens if I delete the app?"
        case UIStringKey.SettingsSupport.faqDeleteAppAnswer:
            return "Locally stored data may be removed from your device when the app is deleted. If iCloud Sync is enabled, your synced data may still remain available through Apple’s iCloud system."

        // SettingsData
        case UIStringKey.SettingsData.deleteAllData:
            return "Delete All Data"
        case UIStringKey.SettingsData.deleteAllDataPrompt:
            return "Delete all data?"
        case UIStringKey.SettingsData.exportData:
            return "Export Data"
        case UIStringKey.SettingsData.importData:
            return "Import Data"
        case UIStringKey.SettingsData.importNow:
            return "Import Now"
        case UIStringKey.SettingsData.importEntryPointDescription:
            return "Use this entry point if you started simple and want to bring historical records into FinTrack later. The same strict CSV contract applies here."
        case UIStringKey.SettingsData.importContractMismatch:
            return "This file does not fully match the current standard CSV contract. Review the preview for exact issues."
        case UIStringKey.SettingsData.importWarningsReady:
            return "The file is ready, but some rows include warnings that you should review before import."
        case UIStringKey.SettingsData.importReady:
            return "The file matches the current CSV contract and is ready for import."
        case UIStringKey.SettingsData.importFinished:
            return "Import finished successfully."
        case UIStringKey.SettingsData.importFailed:
            return "Import failed before completion."
        case UIStringKey.SettingsData.noCSVSelected:
            return "No CSV file was selected."
        case UIStringKey.SettingsData.recurringRules:
            return "Recurring Rules"
        case UIStringKey.SettingsData.thisActionCannotBeUndone:
            return "This action cannot be undone."
        case UIStringKey.SettingsData.transactions:
            return "Transactions"

        // SettingsFinance
        case UIStringKey.SettingsFinance.accomplishedGoals:
            return "Accomplished Goals"
        case UIStringKey.SettingsFinance.currentFinancialProfile:
            return "Current Financial Profile"
        case UIStringKey.SettingsFinance.currentGoals:
            return "Current Goals"
        case UIStringKey.SettingsFinance.currentGoalAccomplished:
            return "Current Goal Accomplished!"
        case UIStringKey.SettingsFinance.currentGoalPaused:
            return "Current Goal Paused"
        case UIStringKey.SettingsFinance.editGoal:
            return "Edit Goal"
        case UIStringKey.SettingsFinance.editSection:
            return "Edit"
        case UIStringKey.SettingsFinance.financialGoal:
            return "Financial Goal"
        case UIStringKey.SettingsFinance.financialProfile:
            return "Financial Profile"
        case UIStringKey.SettingsFinance.goalTitle:
            return "Goal Title"
        case UIStringKey.SettingsFinance.currentNetWorth:
            return "Current Net Worth"
        case UIStringKey.SettingsFinance.includeCurrentAssets:
            return "Include Current Assets"
        case UIStringKey.SettingsFinance.myGoal:
            return "My Goal"
        case UIStringKey.SettingsFinance.noGoalSet:
            return "No goal set"
        case UIStringKey.SettingsFinance.profile:
            return "Profile"
        case UIStringKey.SettingsFinance.progressPercentFormat:
            return "progress_percent_format"
        case UIStringKey.SettingsFinance.saveGoal:
            return "Save Goal"
        case UIStringKey.SettingsFinance.setYourGoal:
            return "Set Your Goal"
        case UIStringKey.SettingsFinance.targetFormat:
            return "Target: %@"
        case UIStringKey.SettingsFinance.assetsFormat:
            return "Assets: %@"
        case UIStringKey.SettingsFinance.availableAssets:
            return "Available Assets"
        case UIStringKey.SettingsFinance.debtFormat:
            return "Debt: %@"
        case UIStringKey.SettingsFinance.depositPrincipal:
            return "Deposit Principal"
        case UIStringKey.SettingsFinance.loansFormat:
            return "Loans: %@"
        case UIStringKey.SettingsFinance.goalCountFormat:
            return "goal_count_format"
        case UIStringKey.SettingsFinance.categoryManagement:
            return "Category Management"
        case UIStringKey.SettingsFinance.categoryManagementSubtitle:
            return "Manage categories"
        case UIStringKey.Export.sharingUnavailable:
            return "Sharing is unavailable for this item."

        // SettingsAccount
        case UIStringKey.SettingsAccount.account:
            return "Account"
        case UIStringKey.SettingsAccount.accountName:
            return "Account Name"
        case UIStringKey.SettingsAccount.accounts:
            return "Accounts"
        case UIStringKey.SettingsAccount.addAccount:
            return "Add Account"
        case UIStringKey.SettingsAccount.cancel:
            return "Cancel"
        case UIStringKey.SettingsAccount.deleteAccountAndResetApp:
            return "Delete Account & Reset App"
        case UIStringKey.SettingsAccount.deleteAccountAndResetAppPrompt:
            return "Delete Account and Reset App?"
        case UIStringKey.SettingsAccount.existingAccounts:
            return "Existing Accounts"
        case UIStringKey.SettingsAccount.finTrackAccount:
            return "FinTrack Account"
        case UIStringKey.SettingsAccount.noAccountsYet:
            return "No accounts yet"
        case UIStringKey.SettingsAccount.notebookName:
            return "Notebook Name"
        case UIStringKey.SettingsAccount.openICloudSync:
            return "iCloud Sync"
        case UIStringKey.SettingsAccount.placeholderDescription:
            return "This screen is a temporary local placeholder for future account and sync work. It does not represent final Apple sign-in or real iCloud sync architecture."
        case UIStringKey.SettingsAccount.placeholderTitle:
            return "Placeholder account layer"
        case UIStringKey.SettingsAccount.saveAccount:
            return "Save Account"
        case UIStringKey.SettingsAccount.saveNotebookName:
            return "Save Notebook Name"
        case UIStringKey.SettingsAccount.settings:
            return "Settings"
        case UIStringKey.SettingsAccount.signInWithApple:
            return "Sign in with Apple"
        case UIStringKey.SettingsAccount.signInRequiredForICloud:
            return "Sign in with Apple is required before enabling iCloud Sync."
        case UIStringKey.SettingsAccount.signOut:
            return "Sign Out"
        case UIStringKey.SettingsAccount.signOutKeepsLocalData:
            return "Sign Out keeps your local data. Delete Account & Reset App signs you out, deletes all local data, disables iCloud Sync, and returns FinTrack to its initial setup state."
        case UIStringKey.SettingsAccount.signOutPrompt:
            return "Sign out?"
        case UIStringKey.SettingsAccount.signOutUnavailableUntilSignIn:
            return "You will keep your local data, but iCloud sync will be unavailable until you sign in again."
        case UIStringKey.SettingsAccount.signedInWithApple:
            return "Signed in with Apple"
        case UIStringKey.SettingsAccount.status:
            return "Status"
        case UIStringKey.SettingsAccount.deleteAccountResetWarning:
            return "This will sign you out, delete all local data, disable iCloud Sync, and return FinTrack to its initial setup state. This action cannot be undone."
        case UIStringKey.SettingsAccount.deleteLocalDataAndResetApp:
            return "Delete Local Data And Reset App"
        case UIStringKey.SettingsAccount.deleteLocalDataAndResetAppSubtitle:
            return "This removes all local records and returns FinTrack to onboarding."
        case UIStringKey.SettingsAccount.deleteLocalDataAndResetAppAlert:
            return "This action removes all local ledger data and cannot be undone."
        case UIStringKey.SettingsAccount.localOnlyStorageDescription:
            return "All data stays on this device. Cloud sync and third-party sign-in are disabled."
        case UIStringKey.SettingsAccount.storageMode:
            return "Storage Mode"
        case UIStringKey.SettingsAccount.local:
            return "Local"
        case UIStringKey.SettingsAccount.importExport:
            return "Import · Export"
        case UIStringKey.SettingsAccount.localOnly:
            return "Local only"
        case UIStringKey.SettingsAccount.continueSetup:
            return "Continue Setup"
        case UIStringKey.SettingsAccount.continueSetupPending:
            return "Pending"
        case UIStringKey.SettingsAccount.continueSetupOptional:
            return "Optional"
        case UIStringKey.SettingsAccount.continueSetupEnabled:
            return "Enabled"
        case UIStringKey.SettingsAccount.continueSetupIntro:
            return "Finish the pieces you skipped during onboarding."
        case UIStringKey.SettingsAccount.continueSetupProgressFormat:
            return "%lld of 3 core setup items done"
        case UIStringKey.SettingsAccount.continueSetupFinancialBaseline:
            return "Financial Baseline"
        case UIStringKey.SettingsAccount.continueSetupFinancialBaselineEmpty:
            return "Add your current assets and debt snapshot."
        case UIStringKey.SettingsAccount.continueSetupFinancialBaselineConfigured:
            return "Review or refresh your latest baseline."
        case UIStringKey.SettingsAccount.continueSetupFinancialGoal:
            return "Financial Goal"
        case UIStringKey.SettingsAccount.continueSetupFinancialGoalEmpty:
            return "Set a target if you want progress tracking."
        case UIStringKey.SettingsAccount.continueSetupFinancialGoalConfigured:
            return "Review or adjust your current goal."
        case UIStringKey.SettingsAccount.continueSetupHistoricalRecords:
            return "Historical Records"
        case UIStringKey.SettingsAccount.continueSetupHistoricalRecordsEmpty:
            return "Import past transactions from a clean CSV."
        case UIStringKey.SettingsAccount.continueSetupHistoricalRecordsConfigured:
            return "Import more history if you want broader context."
        case UIStringKey.SettingsAccount.continueSetupReminders:
            return "Reminders"
        case UIStringKey.SettingsAccount.continueSetupRemindersSubtitle:
            return "Turn on notifications when you want scheduled prompts."

        // Profile
        case UIStringKey.Profile.exportResetSummary:
            return "Export · Reset · Summary"
        case UIStringKey.Profile.goalOff:
            return "Goal off"
        case UIStringKey.Profile.goalOn:
            return "Goal on"
        case UIStringKey.Profile.notSignedIn:
            return "Not signed in"
        case UIStringKey.Profile.profileOff:
            return "Profile off"
        case UIStringKey.Profile.profileOn:
            return "Profile on"
        case UIStringKey.Profile.signedIn:
            return "Signed in"
        case UIStringKey.Profile.syncOff:
            return "Sync off"
        case UIStringKey.Profile.syncOn:
            return "Sync on"
        case UIStringKey.Profile.version:
            return "Version 1.0"

        // Notification
        case UIStringKey.Notification.authorization:
            return "Authorization"
        case UIStringKey.Notification.denied:
            return "Denied"
        case UIStringKey.Notification.depositMaturesInDaysExpectedInterestFormat:
            return "Deposit matures in %lld day(s) • Expected interest %@ %@"
        case UIStringKey.Notification.depositMaturesTodayExpectedInterestFormat:
            return "Deposit matures today • Expected interest %@ %@"
        case UIStringKey.Notification.ephemeral:
            return "Ephemeral"
        case UIStringKey.Notification.finTrackCanDeliverLocalReminderNotificationsNormally:
            return "FinTrack can deliver local reminder notifications normally."
        case UIStringKey.Notification.finTrackCanSendNotificationsQuietlyWithProvisionalAuthorization:
            return "FinTrack can send notifications quietly with provisional authorization."
        case UIStringKey.Notification.finTrackCurrentlyHasTemporaryNotificationAuthorization:
            return "FinTrack currently has temporary notification authorization."
        case UIStringKey.Notification.ifNotificationsDenied:
            return "If notifications are denied, reminders will still be saved in FinTrack, but iPhone will not display notification alerts until permission is enabled in Settings."
        case UIStringKey.Notification.info:
            return "Info"
        case UIStringKey.Notification.notDetermined:
            return "Not Determined"
        case UIStringKey.Notification.notificationAuthorizationStatusCouldNotBeDetermined:
            return "Notification authorization status could not be determined."
        case UIStringKey.Notification.notificationPermissionHasNotBeenRequestedYet:
            return "Notification permission has not been requested yet."
        case UIStringKey.Notification.notificationsAreCurrentlyTurnedOffForFinTrackEnableThemInTheIPhoneSettingsAppToReceiveReminders:
            return "Notifications are currently turned off for FinTrack. Enable them in the iPhone Settings app to receive reminders."
        case UIStringKey.Notification.notifications:
            return "Notifications"
        case UIStringKey.Notification.openSystemSettings:
            return "Open System Settings"
        case UIStringKey.Notification.provisional:
            return "Provisional"
        case UIStringKey.Notification.recurringAndDepositReminders:
            return "Recurring transaction reminders and deposit maturity reminders use local notifications on this device."
        case UIStringKey.Notification.recurringReminderFormat:
            return "Recurring %@ reminder • %@ • %@ %@"
        case UIStringKey.Notification.refreshStatus:
            return "Refresh Status"
        case UIStringKey.Notification.requestPermission:
            return "Request Permission"
        case UIStringKey.Notification.status:
            return "Status"
        case UIStringKey.Notification.unknown:
            return "Unknown"
        case UIStringKey.Notification.upcomingRecurringInDaysFormat:
            return "Upcoming recurring %@ in %lld day(s) • %@ • %@ %@"
        case UIStringKey.Notification.authorized:
            return "Authorized"

        case UIStringKey.App.record:
            return "Record"
        case UIStringKey.App.insights:
            return "Insights"
        case UIStringKey.App.settings:
            return "Settings"
        case UIStringKey.Insights.all:
            return "All"
        case UIStringKey.Insights.allGoalsPausedOrAccomplished:
            return "All goals paused or accomplished"
        case UIStringKey.Insights.categoryBreakdownTitle:
            return "Category Breakdown"
        case UIStringKey.Insights.compareLockedSubtitle:
            return "Compare unlocks when multiple years of data are available"
        case UIStringKey.Insights.compareReadySubtitle:
            return "Historical data spans multiple years and is ready for comparison"
        case UIStringKey.Insights.compareSectionTitle:
            return "Compare"
        case UIStringKey.Insights.compareDetailTitle:
            return "Compare"
        case UIStringKey.Insights.compareDefaultRouteTitle:
            return "Default Compare"
        case UIStringKey.Insights.compareCustomRouteTitle:
            return "Custom Compare"
        case UIStringKey.Insights.compareRouteSectionTitle:
            return "Mode"
        case UIStringKey.Insights.compareCurrentLabel:
            return "Current"
        case UIStringKey.Insights.compareCurrentDateTitle:
            return "Current"
        case UIStringKey.Insights.compareDeltaPercentFormat:
            return "%+.0f%%"
        case UIStringKey.Insights.compareDeltaPercentNoBaseline:
            return "No safe percent because last year was near zero"
        case UIStringKey.Insights.compareDeclineDriversTitle:
            return "Down"
        case UIStringKey.Insights.compareDriversSectionTitle:
            return "Drivers"
        case UIStringKey.Insights.compareExpenseCardTitle:
            return "Spending"
        case UIStringKey.Insights.compareGrowthDriversTitle:
            return "Up"
        case UIStringKey.Insights.compareLargestGapCardTitle:
            return "Gap"
        case UIStringKey.Insights.compareNetCardTitle:
            return "Net"
        case UIStringKey.Insights.compareNoDeclineDriversTitle:
            return "No down drivers"
        case UIStringKey.Insights.compareNoGrowthDriversTitle:
            return "No up drivers"
        case UIStringKey.Insights.comparePatternCardTitle:
            return "Pattern"
        case UIStringKey.Insights.comparePatternConcentratedFormat:
            return "Most of the difference is concentrated in %@, rather than spread evenly across the selected period."
        case UIStringKey.Insights.comparePatternDeclineDriverFormat:
            return "The gap is offset most clearly by declines in %@, which reduces last period's pressure."
        case UIStringKey.Insights.comparePatternGrowthDriverFormat:
            return "The change is driven most clearly by %@, which contributes the largest category increase."
        case UIStringKey.Insights.comparePatternHigherBaseline:
            return "Spending is higher than the other side across most of the selected period, suggesting a higher baseline."
        case UIStringKey.Insights.comparePatternInsufficientData:
            return "There is not enough data yet to derive a stable pattern."
        case UIStringKey.Insights.comparePatternLowerBaseline:
            return "Spending is lower than the other side across most of the selected period, suggesting a lighter baseline."
        case UIStringKey.Insights.comparePatternMinimalChange:
            return "The current and previous periods are close, with no strong change pattern detected."
        case UIStringKey.Insights.comparePatternMultiDriverChange:
            return "The change is driven by multiple categories rather than a single dominant driver."
        case UIStringKey.Insights.comparePatternNoComparable:
            return "There is not enough comparable data yet."
        case UIStringKey.Insights.comparePatternSingleDriverDecrease:
            return "%@ is driving the biggest decrease."
        case UIStringKey.Insights.comparePatternSingleDriverIncrease:
            return "%@ is driving the biggest increase."
        case UIStringKey.Insights.comparePatternSpread:
            return "The difference is spread fairly evenly across the selected period, with no single dominant spike."
        case UIStringKey.Insights.comparePatternSectionTitle:
            return "Pattern"
        case UIStringKey.Insights.comparePreviousLabel:
            return "Previous"
        case UIStringKey.Insights.comparePreviousDateTitle:
            return "Previous"
        case UIStringKey.Insights.compareTargetSectionTitle:
            return "Comparison"
        case UIStringKey.Insights.comparePreviousYearFormat:
            return "%lld year to date"
        case UIStringKey.Insights.compareCurrentYearFormat:
            return "%lld year to date"
        case UIStringKey.Insights.compareSameMonthCardTitle:
            return "Month"
        case UIStringKey.Insights.compareSameMonthDriverDeclineFormat:
            return "%@ is reducing the gap the most."
        case UIStringKey.Insights.compareSameMonthDriverGrowthFormat:
            return "%@ is driving the biggest increase."
        case UIStringKey.Insights.compareSameMonthNoDriver:
            return "No single category stands out."
        case UIStringKey.Insights.compareSameMonthSectionTitle:
            return "Selected Month"
        case UIStringKey.Insights.compareSamePeriodSubtitleFormat:
            return "Through month %lld this year"
        case UIStringKey.Insights.compareSummarySectionTitle:
            return "Summary"
        case UIStringKey.Insights.compareTeaserCoverageFormat:
            return "%lld / 12 active months"
        case UIStringKey.Insights.compareTeaserHeadlineFormat:
            return "%lld vs %lld"
        case UIStringKey.Insights.compareTeaserSubtitle:
            return "A lightweight year-over-year preview is ready"
        case UIStringKey.Insights.compareTeaserSummaryFormat:
            return "%lld active months this year · %lld last year"
        case UIStringKey.Insights.compareTeaserTitle:
            return "Compare"
        case UIStringKey.Insights.compareTrendSectionTitle:
            return "Trend"
        case UIStringKey.Insights.compareTrendQuarterQ1:
            return "Q1"
        case UIStringKey.Insights.compareTrendQuarterQ2:
            return "Q2"
        case UIStringKey.Insights.compareTrendQuarterQ3:
            return "Q3"
        case UIStringKey.Insights.compareTrendQuarterQ4:
            return "Q4"
        case UIStringKey.Insights.categoryBreakdownLockedSubtitle:
            return "Switch to income or expense to explain what is driving the current movement"
        case UIStringKey.Insights.categoryBreakdownLockedTitle:
            return "Category breakdown is unavailable for net view"
        case UIStringKey.Insights.categoryBreakdownNoDataSubtitle:
            return "Add more records in this window to surface meaningful category drivers"
        case UIStringKey.Insights.categoryBreakdownNoDataTitle:
            return "Not enough category data yet"
        case UIStringKey.Insights.depositBalanceSubtitle:
            return "All deposit principals and credited interest"
        case UIStringKey.Insights.depositBalanceTitle:
            return "Deposit Balance"
        case UIStringKey.Insights.expenseTitle:
            return "Expense"
        case UIStringKey.Insights.goalProgressTitle:
            return "Goal Progress"
        case UIStringKey.Insights.incomeTitle:
            return "Income"
        case UIStringKey.Insights.incomeBreakdownTitle:
            return "Income Breakdown"
        case UIStringKey.Insights.netTitle:
            return "Net"
        case UIStringKey.Insights.netSubtitle:
            return "Income - Expense"
        case UIStringKey.Insights.netWorthSubtitle:
            return "Current baseline after assets and liabilities"
        case UIStringKey.Insights.netWorthTitle:
            return "Net Worth"
        case UIStringKey.Insights.insightsTitle:
            return "Insights"
        case UIStringKey.Insights.itemSummaryFormat:
            return "%@ • %@"
        case UIStringKey.Insights.loanBalanceSubtitle:
            return "Outstanding principal"
        case UIStringKey.Insights.loanBalanceTitle:
            return "Loan Balance"
        case UIStringKey.Insights.matures:
            return "Matures"
        case UIStringKey.Insights.month:
            return "Month"
        case UIStringKey.Insights.nextSectionSubtitle:
            return "Upcoming deadlines and pressure points"
        case UIStringKey.Insights.nextSectionTitle:
            return "Next / Alerts"
        case UIStringKey.Insights.nextSectionClearSubtitle:
            return "No upcoming loan payments or obvious pressure points in the current dataset"
        case UIStringKey.Insights.nextSectionClearTitle:
            return "Nothing urgent right now"
        case UIStringKey.Insights.nextDepositInterestTitle:
            return "Next Deposit Interest"
        case UIStringKey.Insights.nextLoanPaymentTitle:
            return "Next Loan Payment"
        case UIStringKey.Insights.nextPayout:
            return "Next payout"
        case UIStringKey.Insights.noActiveLoans:
            return "No active loans"
        case UIStringKey.Insights.noExpenseData:
            return "No expense data"
        case UIStringKey.Insights.noGoalSet:
            return "No goal set"
        case UIStringKey.Insights.noIncomeData:
            return "No income data"
        case UIStringKey.Insights.noUpcomingPayment:
            return "No upcoming payment"
        case UIStringKey.Insights.overviewSectionSubtitle:
            return "How you are doing in the selected period"
        case UIStringKey.Insights.overviewSectionTitle:
            return "Overview"
        case UIStringKey.Insights.pieModeExpense:
            return "Expense"
        case UIStringKey.Insights.pieModeIncome:
            return "Income"
        case UIStringKey.Insights.range:
            return "Range"
        case UIStringKey.Insights.barModeExpense:
            return "Expense"
        case UIStringKey.Insights.barModeIncome:
            return "Income"
        case UIStringKey.Insights.barModeNet:
            return "Net"
        case UIStringKey.Insights.recurringExpenseTitle:
            return "Recurring Expense"
        case UIStringKey.Insights.recurringIncomeTitle:
            return "Recurring Income"
        case UIStringKey.Insights.reviewMonthlySubtitle:
            return "A future monthly wrap-up entry point will plug in here without changing the main Insights structure."
        case UIStringKey.Insights.reviewMonthlyTitle:
            return "Monthly Summary"
        case UIStringKey.Insights.reviewPlaceholderBadge:
            return "Coming later"
        case UIStringKey.Insights.reviewPlaceholderMessage:
            return "This placeholder keeps a clean navigation target ready for future summary work."
        case UIStringKey.Insights.reviewPlaceholderSubtitle:
            return "No monthly or yearly report engine is built yet in this phase."
        case UIStringKey.Insights.reviewSectionSubtitle:
            return "Future review entry points live here so deeper summaries can plug in without reshaping Insights again."
        case UIStringKey.Insights.reviewSectionTitle:
            return "Review"
        case UIStringKey.Insights.reviewYearlySubtitle:
            return "A future yearly wrap-up entry point will reuse compare-ready analytics from this architecture."
        case UIStringKey.Insights.reviewYearlyTitle:
            return "Yearly Summary"
        case UIStringKey.Insights.resumeOrCreateGoal:
            return "Resume or create a goal to track progress"
        case UIStringKey.Insights.savingsRateTitle:
            return "Savings Rate"
        case UIStringKey.Insights.savingsRateSubtitle:
            return "Selected period"
        case UIStringKey.Insights.setGoalInSettings:
            return "Set a goal in Settings"
        case UIStringKey.Insights.targetFormat:
            return "Target: %@"
        case UIStringKey.Insights.topExpenseTitle:
            return "Top Expense"
        case UIStringKey.Insights.topExpenseCategoryTitle:
            return "Top Expense Category"
        case UIStringKey.Insights.topExpenseDrilldownHint:
            return "Open income or expense detail to inspect category movement."
        case UIStringKey.Insights.topIncomeTitle:
            return "Top Income"
        case UIStringKey.Insights.trendSectionSubtitle:
            return "Movement inside the current window"
        case UIStringKey.Insights.trendSectionTitle:
            return "Trend"
        case UIStringKey.Insights.trendUnavailableForCustomRangeSubtitle:
            return "Choose week, month, year, or all to see movement over time"
        case UIStringKey.Insights.trendUnavailableForCustomRangeTitle:
            return "Trend unavailable for custom range"
        case UIStringKey.Insights.week:
            return "Week"
        case UIStringKey.Insights.year:
            return "Year"

        // Record
        case UIStringKey.Record.deposits:
            return "Deposits"
        case UIStringKey.Record.depositsSubtitle:
            return key
        case UIStringKey.Record.loanPayment:
            return "Loan Payment"
        case UIStringKey.Record.loans:
            return "Loans"
        case UIStringKey.Record.loansSubtitle:
            return key
        case UIStringKey.Record.more:
            return "More"
        case UIStringKey.Record.noTransactionsYet:
            return "No transactions yet"
        case UIStringKey.Record.quickRecord:
            return "Quick Record"
        case UIStringKey.Record.recent:
            return "Recent"
        case UIStringKey.Record.record:
            return "Record"
        case UIStringKey.Record.recurring:
            return "Recurring"
        case UIStringKey.Record.recurringSubtitle:
            return key
        case UIStringKey.Record.recordHistoryHint:
            return "Start tracking your money by adding your first"
        case UIStringKey.Record.searchCategory:
            return "Search Category"
        case UIStringKey.Record.searchEnd:
            return "End"
        case UIStringKey.Record.searchStart:
            return "Start"
        case UIStringKey.Record.todaySpend:
            return key

        // Transaction
        case UIStringKey.Transaction.exchangeRateAutoFilledFormat:
            return "Auto-filled · %@"
        case UIStringKey.Transaction.exchangeRateAutoFilledLive:
            return "Auto-filled from live exchange data"
        case UIStringKey.Transaction.exchangeRateLoading:
            return "Loading rate…"
        case UIStringKey.Transaction.exchangeRateRefreshing:
            return "Refreshing rate…"
        case UIStringKey.Transaction.exchangeRateSavedSnapshot:
            return "Saved snapshot"

        // Loan
        case UIStringKey.Loan.amortizationSchedule:
            return "Amortization Schedule"
        case UIStringKey.Loan.annualRate:
            return "Annual Rate"
        case UIStringKey.Loan.autoFilledDateFormat:
            return "Auto-filled · %@"
        case UIStringKey.Loan.autoFilledFromLiveData:
            return "Auto-filled from live exchange data"
        case UIStringKey.Loan.createLoan:
            return "Create Loan"
        case UIStringKey.Loan.currency:
            return "Currency"
        case UIStringKey.Loan.delete:
            return "Delete"
        case UIStringKey.Loan.downPayment:
            return "Down Payment"
        case UIStringKey.Loan.downPaymentInvalid:
            return "Down payment must be lower than total amount."
        case UIStringKey.Loan.downPaymentPercent:
            return "Down Payment %"
        case UIStringKey.Loan.editLoan:
            return "Edit Loan"
        case UIStringKey.Loan.estimatedMonthlyPayment:
            return "Estimated Monthly Payment"
        case UIStringKey.Loan.estimatedLastPayment:
            return "Estimated Last Payment"
        case UIStringKey.Loan.exchangeRate:
            return "Exchange Rate"
        case UIStringKey.Loan.financed:
            return "Financed"
        case UIStringKey.Loan.financedAmountFormat:
            return "loan_financed_amount_format"
        case UIStringKey.Loan.first:
            return "First"
        case UIStringKey.Loan.firstPayment:
            return "First Payment"
        case UIStringKey.Loan.firstPaymentDate:
            return "First Payment Date"
        case UIStringKey.Loan.foreignCurrencyHint:
            return "For foreign-currency entries, the exchange rate will be calculated automatically using the rate on the posting date. If you need to adjust it later, edit the transaction from preview."
        case UIStringKey.Loan.interest:
            return "Interest"
        case UIStringKey.Loan.last:
            return "Last"
        case UIStringKey.Loan.lastPayment:
            return "Last Payment"
        case UIStringKey.Loan.loadingRate:
            return "Loading rate…"
        case UIStringKey.Loan.loanRecurringPaymentTitleFormat:
            return "loan_recurring_payment_title_format"
        case UIStringKey.Loan.loanPaymentIndexFormat:
            return "loan_payment_index_format"
        case UIStringKey.Loan.loanPrincipalComponentFormat:
            return "loan_principal_component_format"
        case UIStringKey.Loan.loanInterestComponentFormat:
            return "loan_interest_component_format"
        case UIStringKey.Loan.loanBalanceFormat:
            return "loan_balance_format"
        case UIStringKey.Loan.loanStartDateFormat:
            return "loan_start_date_format"
        case UIStringKey.Loan.loanTermRateCategoryFormat:
            return "loan_term_rate_category_format"
        case UIStringKey.Loan.loans:
            return "Loans"
        case UIStringKey.Loan.method:
            return "Method"
        case UIStringKey.Loan.monthly:
            return "Monthly"
        case UIStringKey.Loan.months:
            return "Months"
        case UIStringKey.Loan.mortgage:
            return "Mortgage"
        case UIStringKey.Loan.newLoan:
            return "New Loan"
        case UIStringKey.Loan.noLoansYet:
            return "No loans yet"
        case UIStringKey.Loan.notes:
            return "Notes"
        case UIStringKey.Loan.optionalNote:
            return "Optional note"
        case UIStringKey.Loan.overview:
            return "Overview"
        case UIStringKey.Loan.payments:
            return "Payments"
        case UIStringKey.Loan.percentPresetFormat:
            return "loan_percent_preset_format"
        case UIStringKey.Loan.preview:
            return "Preview"
        case UIStringKey.Loan.principal:
            return "Principal"
        case UIStringKey.Loan.principalInterestNoteFormat:
            return "loan_principal_interest_note_format"
        case UIStringKey.Loan.refreshingRate:
            return "Refreshing rate…"
        case UIStringKey.Loan.repayment:
            return "Repayment"
        case UIStringKey.Loan.repaymentMethod:
            return "Repayment Method"
        case UIStringKey.Loan.saveChanges:
            return "Save Changes"
        case UIStringKey.Loan.savedSnapshot:
            return "Saved snapshot"
        case UIStringKey.Loan.schedule:
            return "Schedule"
        case UIStringKey.Loan.setTerm:
            return "Set term"
        case UIStringKey.Loan.summary:
            return "Summary"
        case UIStringKey.Loan.term:
            return "Term"
        case UIStringKey.Loan.termMonthsFormat:
            return "%lld months"
        case UIStringKey.Loan.thisNoteWillBeCopied:
            return "This note will be copied into generated repayment records."
        case UIStringKey.Loan.title:
            return "Title"
        case UIStringKey.Loan.total:
            return "Total"
        case UIStringKey.Loan.totalAmount:
            return "Total Amount"
        case UIStringKey.Loan.totalBreakdownFormat:
            return "Total %@ · Down %@ · Financed %@"
        case UIStringKey.Loan.totalInterest:
            return "Total Interest"
        case UIStringKey.Loan.totalMinusDownPaymentHint:
            return "Total amount minus down payment will be used as the financed principal."
        case UIStringKey.Loan.totalRepayment:
            return "Total Repayment"
        case UIStringKey.Loan.updateLoanHint:
            return "Updating a loan rebuilds its repayment schedule and replaces generated recurring rules."
        case UIStringKey.Loan.years:
            return "Years"
        case UIStringKey.Loan.yr:
            return "yr"
        case UIStringKey.Loan.mo:
            return "mo"

        // Deposit
        case UIStringKey.Deposit.active:
            return "Active"
        case UIStringKey.Deposit.amount:
            return "Amount"
        case UIStringKey.Deposit.annualInterestRate:
            return "Annual Interest Rate"
        case UIStringKey.Deposit.autoPredictionCustomisable:
            return "Auto prediction, customisable."
        case UIStringKey.Deposit.carryover:
            return "Carryover"
        case UIStringKey.Deposit.carryoverBreakdownFormat:
            return "Carryover principal %@ · carryover interest %@"
        case UIStringKey.Deposit.closed:
            return "Closed"
        case UIStringKey.Deposit.createDeposit:
            return "Create Deposit"
        case UIStringKey.Deposit.currency:
            return "Currency"
        case UIStringKey.Deposit.delete:
            return "Delete"
        case UIStringKey.Deposit.deposits:
            return "Deposits"
        case UIStringKey.Deposit.editDeposit:
            return "Edit Deposit"
        case UIStringKey.Deposit.expectedInterest:
            return "Expected Interest"
        case UIStringKey.Deposit.foreignCurrencyHint:
            return "For foreign-currency entries, the exchange rate will be calculated automatically using the rate on the posting date. If you need to adjust it later, edit the transaction from preview."
        case UIStringKey.Deposit.interest:
            return "Interest"
        case UIStringKey.Deposit.interestSetup:
            return "Interest Setup"
        case UIStringKey.Deposit.interestSnapshotHint:
            return "Interest and exchange-rate snapshots are preserved using your selected dates."
        case UIStringKey.Deposit.maturedDeposits:
            return "Matured Deposits"
        case UIStringKey.Deposit.maturity:
            return "Maturity"
        case UIStringKey.Deposit.maturityDate:
            return "Maturity Date"
        case UIStringKey.Deposit.maturityInterest:
            return "Maturity Interest"
        case UIStringKey.Deposit.maturityInterestPayoutDescription:
            return "Interest is recorded as income at maturity and stays available for spending or transfer."
        case UIStringKey.Deposit.maturityInterestRolloverDescription:
            return "Interest is still recorded in Recent Transactions as income, but is intended to roll into the next deposit principal."
        case UIStringKey.Deposit.monthlyInterest:
            return "Monthly Interest"
        case UIStringKey.Deposit.name:
            return "Name"
        case UIStringKey.Deposit.newDeposit:
            return "New Deposit"
        case UIStringKey.Deposit.noDepositsYet:
            return "No deposits yet"
        case UIStringKey.Deposit.ok:
            return "OK"
        case UIStringKey.Deposit.optionalNote:
            return "Optional note"
        case UIStringKey.Deposit.overview:
            return "Overview"
        case UIStringKey.Deposit.preferences:
            return "Preferences"
        case UIStringKey.Deposit.payout:
            return "Payout"
        case UIStringKey.Deposit.rate:
            return "Rate"
        case UIStringKey.Deposit.remindBefore:
            return "Remind Before"
        case UIStringKey.Deposit.reminder:
            return "Reminder"
        case UIStringKey.Deposit.reminderTime:
            return "Reminder Time"
        case UIStringKey.Deposit.rollover:
            return "Rollover"
        case UIStringKey.Deposit.rolloverFrom:
            return "Rollover From"
        case UIStringKey.Deposit.rolloverSource:
            return "Rollover Source"
        case UIStringKey.Deposit.rolloverSourceHint:
            return "Optionally link this deposit to a matured deposit marked for rollover."
        case UIStringKey.Deposit.sameDay:
            return "Same day"
        case UIStringKey.Deposit.saveChanges:
            return "Save Changes"
        case UIStringKey.Deposit.settlement:
            return "Settlement"
        case UIStringKey.Deposit.startDate:
            return "Start Date"
        case UIStringKey.Deposit.timeline:
            return "Timeline"
        case UIStringKey.Deposit.totalInterest:
            return "Total Interest"
        case UIStringKey.Deposit.unableToSaveDeposit:
            return "Unable to Save Deposit"
        case UIStringKey.Deposit.oneDayBefore:
            return "1 day before"
        case UIStringKey.Deposit.threeDaysBefore:
            return "3 days before"
        case UIStringKey.Deposit.sevenDaysBefore:
            return "7 days before"

        // Recurring
        case UIStringKey.Recurring.active:
            return "Active"
        case UIStringKey.Recurring.amount:
            return "Amount"
        case UIStringKey.Recurring.cadence:
            return "Cadence"
        case UIStringKey.Recurring.category:
            return "Category"
        case UIStringKey.Recurring.createRule:
            return "Create Rule"
        case UIStringKey.Recurring.currency:
            return "Currency"
        case UIStringKey.Recurring.customCategory:
            return "Custom category"
        case UIStringKey.Recurring.delete:
            return "Delete"
        case UIStringKey.Recurring.editRecurring:
            return "Edit Recurring"
        case UIStringKey.Recurring.end:
            return "End"
        case UIStringKey.Recurring.endDate:
            return "End Date"
        case UIStringKey.Recurring.every:
            return "Every"
        case UIStringKey.Recurring.everyIntervalFormat:
            return "Every %d %@"
        case UIStringKey.Recurring.everyScheduleFormat:
            return "Every %d %@ • %@"
        case UIStringKey.Recurring.expense:
            return "Expense"
        case UIStringKey.Recurring.foreignCurrencyHint:
            return "For foreign-currency entries, the exchange rate will be calculated automatically using the rate on the posting date. If you need to adjust it later, edit the transaction from preview."
        case UIStringKey.Recurring.hasEndDate:
            return "Has End Date"
        case UIStringKey.Recurring.income:
            return "Income"
        case UIStringKey.Recurring.interval:
            return "Interval"
        case UIStringKey.Recurring.newRecurring:
            return "New Recurring"
        case UIStringKey.Recurring.next:
            return "Next"
        case UIStringKey.Recurring.nextExecution:
            return "Next Execution"
        case UIStringKey.Recurring.noEndDate:
            return "No end date"
        case UIStringKey.Recurring.noRecurringTransactionsYet:
            return "No recurring transactions yet"
        case UIStringKey.Recurring.notes:
            return "Notes"
        case UIStringKey.Recurring.ok:
            return "OK"
        case UIStringKey.Recurring.optionalNote:
            return "Optional note"
        case UIStringKey.Recurring.overview:
            return "Overview"
        case UIStringKey.Recurring.paused:
            return "Paused"
        case UIStringKey.Recurring.recurring:
            return "Recurring"
        case UIStringKey.Recurring.recurringHint:
            return "Recurring transactions use the posting date to capture exchange-rate snapshots and generated records inherit your selected category."
        case UIStringKey.Recurring.remindBefore:
            return "Remind Before"
        case UIStringKey.Recurring.reminder:
            return "Reminder"
        case UIStringKey.Recurring.reminderTime:
            return "Reminder Time"
        case UIStringKey.Recurring.sameDay:
            return "Same day"
        case UIStringKey.Recurring.saveChanges:
            return "Save Changes"
        case UIStringKey.Recurring.schedule:
            return "Schedule"
        case UIStringKey.Recurring.title:
            return "Title"
        case UIStringKey.Recurring.type:
            return "Type"
        case UIStringKey.Recurring.unableToSaveRule:
            return "Unable to Save Rule"
        case UIStringKey.Recurring.oneDayBefore:
            return "1 day before"

        // Keyboard
        case UIStringKey.Keyboard.clear:
            return "C"
        default:
            return key
        }
    }
}
