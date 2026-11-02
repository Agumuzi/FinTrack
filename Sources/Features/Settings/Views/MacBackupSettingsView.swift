import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct MacBackupRecord: Codable, Identifiable {
    var id = UUID()
    var name: String
    var path: String
    var date: Date
    var size: Int
    var sha256: String
}

struct MacBackupSettingsView: View {
    @ObservedObject private var localizationState = LocalizationController.shared
    var wide: Bool
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var feedback: MacOperationFeedbackCenter
    @ObservedObject private var operation=MacDataOperationState.shared
    @State private var pendingFeedback: MacOperationFeedbackCenter.Notice?
    @AppStorage("base_currency") private var baseCurrency = "USD"
    @AppStorage("fintrack_initial_setup_complete") private var setup = false
    @AppStorage("v2_backup_history") private var historyBytes = Data()
    @AppStorage("v2_backup_folder") private var backupFolder = ""
    @AppStorage("v2_backup_naming") private var naming = "datetime"
    @State private var selectedBackups = Set<UUID>()
    @State private var confirmDeleteBackups = false
    @State private var historyLimit = 8
    @State private var message: String?
    @State private var error: String?
    @State private var exportRange = "全部时间"
    @State private var csvKind = MacCSVKind.transactions
    private struct NativeReview: Identifiable {
        var id = UUID()
        var data: Data
        var payload: MacNativeBackup.Payload
        var filename: String
    }
    private struct CSVReview: Identifiable { var id = UUID(); var preview: MacCSV.Preview; var filename: String }
    @State private var nativeReview: NativeReview?
    @State private var csvReview: CSVReview?
    @State private var restoreText = ""
    @State private var includeUpdateTrust = false
    private var history: [MacBackupRecord] { MacBackupHistory.normalized((try? JSONDecoder().decode([MacBackupRecord].self, from: historyBytes)) ?? []) }
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(15)) {
            MacSettingsColumns(wide: wide) {
                VStack(spacing: MacUI.space(15)) {
                    MacSettingsCard(title: L10n.text("mac.backupSettingsView.MacSettingsColumns.cd4f23cd03"), icon: "externaldrive.badge.plus", subtitle: L10n.text("mac.backupSettingsView.MacSettingsColumns.d86672ab77"), headerColor: .blue, action: AnyView(Button(L10n.text("mac.backupSettingsView.AnyView.e5c63ce7ff")) { createBackup() }.buttonStyle(MacSettingsButtonStyle(primary: true)).accessibilityIdentifier("createNativeBackup"))) {
                        MacSettingsRow(label: L10n.text("mac.backupSettingsView.MacSettingsColumns.d61e028b2d"), labelWidth: 125) {
                            HStack(spacing: MacUI.space(8)) { Image(systemName: "folder.fill").foregroundStyle(.blue); Text(backupFolder.isEmpty ? (MacSettingsVisual.preview ? "~/FinTrack/Backups" : L10n.text("mac.backupSettingsView.MacSettingsColumns.68929c5c15")) : backupFolder.replacingOccurrences(of: NSHomeDirectory(), with: "~")).appFont(.caption, weight: .regular, design: .default).lineLimit(1).truncationMode(.middle); Spacer(minLength: 0); Button(L10n.text("mac.backupSettingsView.MacSettingsColumns.d7392d66de")) { chooseFolder() } }
                        }
                        MacSettingsRow(label: L10n.text("mac.backupSettingsView.MacSettingsColumns.3df3f90a59"), labelWidth: 100) { MacSettingsMenu(selection: $naming, options: [(L10n.text("mac.backupSettingsView.MacSettingsMenu.66fb3f4cf9"),"datetime"), (L10n.text("mac.backupSettingsView.MacSettingsMenu.4080c15939"),"date")]).accessibilityIdentifier("backupNamingMenu") }
                        Text(L10n.text("mac.backupSettingsView.MacSettingsColumns.a29f606944"))
                            .appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    MacSettingsCard(title: L10n.text("mac.backupSettingsView.MacSettingsColumns.3ad98bf875"), icon: "clock.arrow.circlepath", subtitle: L10n.text("mac.backupSettingsView.MacSettingsColumns.c592d13677"), headerColor: .green) {
                        Text(L10n.text("mac.backupSettingsView.MacSettingsColumns.a896625ca3")).appFont(.caption).foregroundStyle(.secondary)
                        VStack(spacing: MacUI.space(0)) {
                            if history.isEmpty { Text(L10n.text("mac.backupSettingsView.MacSettingsColumns.ace937d326")).appFont(.body, weight: .regular, design: .default).foregroundStyle(.secondary).appPadding(25) }
                            ForEach(history.prefix(historyLimit)) { record in
                                Button { if selectedBackups.contains(record.id) { selectedBackups.remove(record.id) } else { selectedBackups.insert(record.id) } } label: {
                                    backupHistoryRow(record)
                                }.buttonStyle(MacInteractiveButtonStyle())
                                Divider()
                            }
                        }
                        if history.count > historyLimit { Button(L10n.format("mac.backupSettingsView.MacSettingsColumns.c2b370c669", Int64(history.count))) { historyLimit = history.count } }
                        HStack { Button(L10n.text("mac.backupSettingsView.MacSettingsColumns.fbe8d3112a"), systemImage: "folder") { showFolder() }.appFont(.caption, weight: .regular, design: .default); Spacer(); Button(L10n.text("mac.backupSettingsView.MacSettingsColumns.a830abd005"), role: .destructive) { confirmDeleteBackups = true }.disabled(selectedBackups.isEmpty).appFont(.caption, weight: .regular, design: .default) }
                    }
                    MacSettingsCard(title: L10n.text("mac.backupSettingsView.MacSettingsColumns.7b09515423"), icon: "arrow.counterclockwise", subtitle: L10n.text("mac.backupSettingsView.MacSettingsColumns.742d29d0bc"), headerColor: .purple, action: AnyView(Button(L10n.text("mac.backupSettingsView.AnyView.4a5cfe5561")) { previewNative() }.accessibilityIdentifier("previewNativeRestore"))) {
                        Label(L10n.text("mac.backupSettingsView.MacSettingsColumns.42cc4a5ad3"), systemImage: "exclamationmark.circle.fill").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.red).appPadding(12).frame(maxWidth: .infinity, alignment: .leading).background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            } right: {
                VStack(spacing: MacUI.space(15)) {
                    MacSettingsCard(title: L10n.text("mac.backupSettingsView.MacSettingsColumns.e8386ba0a8"), icon: "doc.badge.arrow.up", subtitle: L10n.text("mac.backupSettingsView.MacSettingsColumns.13482e6ef1"), headerColor: .orange) {
                        MacSettingsRow(label: L10n.text("mac.backupSettingsView.MacSettingsColumns.df49776bfd"), labelWidth: 90) {
                            MacSettingsMenu(selection: Binding(get: { csvKind.rawValue }, set: { csvKind = MacCSVKind(rawValue: $0) ?? .transactions }), options: MacCSVKind.allCases.map { ($0.title, $0.rawValue) }).accessibilityIdentifier("csvDataKind")
                        }
                        if csvKind == .transactions {
                            MacSettingsRow(label: L10n.text("mac.backupSettingsView.MacSettingsColumns.ced3a1c573"), labelWidth: 100) { MacSettingsMenu(selection: $exportRange, options: [(L10n.text("mac.backupSettingsView.MacSettingsMenu.b28e2113fe"), "全部时间"), (L10n.text("mac.backupSettingsView.MacSettingsMenu.0eeecd26f2"), "本月"), (L10n.text("mac.backupSettingsView.MacSettingsMenu.78ebb7f81d"), "本年")]).accessibilityIdentifier("backupExportRangeMenu") }
                        }
                        Button { exportCSVTemplate() } label: { Text(L10n.text("mac.backupSettingsView.MacSettingsColumns.6413671e3f")).frame(maxWidth: .infinity) }.accessibilityIdentifier("exportCSVTemplate")
                        Button { exportTypedCSV() } label: { Text(L10n.format("mac.backupSettingsView.MacSettingsColumns.bc23c82f50", "\(csvKind.title)")).frame(maxWidth: .infinity) }.accessibilityIdentifier("exportCSVBackup")
                        Text(L10n.text("mac.backupSettingsView.MacSettingsColumns.fc1de61596")).appFont(.caption).foregroundStyle(.secondary)
                        DisclosureGroup(L10n.text("mac.backupSettingsView.DisclosureGroup.dc8049171c")) {
                            Text(L10n.text("mac.backupSettingsView.DisclosureGroup.0d379a31e6")).appFont(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    MacSettingsCard(title: L10n.text("mac.backupSettingsView.MacSettingsColumns.955e6f6be0"), icon: "square.and.arrow.down", subtitle: L10n.format("mac.backupSettingsView.MacSettingsColumns.7e2005acc2", "\(csvKind.title)"), headerColor: .green) {
                        Button { previewCSV() } label: { Text(L10n.format("mac.backupSettingsView.MacSettingsColumns.45d9e8d09c", "\(csvKind.title)")).frame(maxWidth: .infinity) }.accessibilityIdentifier("previewCSVImport")
                        Text(L10n.text("mac.backupSettingsView.MacSettingsColumns.530cc86a36")).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        DisclosureGroup(L10n.text("mac.backupSettingsView.DisclosureGroup.b3ce141d75")) {
                            Button(L10n.text("mac.backupSettingsView.DisclosureGroup.a9e19dd16d")) { exportLegacyCSV() }.accessibilityIdentifier("exportLegacyCSV")
                            Button(L10n.text("mac.backupSettingsView.DisclosureGroup.771c192c8c")) { previewCSV(legacy: true) }.accessibilityIdentifier("previewLegacyCSVImport")
                            Text(L10n.text("mac.backupSettingsView.DisclosureGroup.d8dd3588de")).appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                        }.appFont(.caption, weight: .regular)
                    }
                }
            }
            if let message { Text(message).appFont(.caption, weight: .regular).foregroundStyle(.green).accessibilityIdentifier("backupMessage") }
            if let error { Text(error).appFont(.caption, weight: .regular).foregroundStyle(.red).textSelection(.enabled).accessibilityIdentifier("backupError") }
        }
        .disabled(operation.status != nil)
        .overlay {if let status=operation.status {ProgressView(status).padding(24).background(.regularMaterial,in:RoundedRectangle(cornerRadius:12)).accessibilityIdentifier("dataOperationProgress")}}
        .alert(L10n.text("mac.backupSettingsView.body.be9f090b6f"), isPresented: $confirmDeleteBackups) {
            Button(L10n.text("mac.backupSettingsView.body.2cd0f3be87"), role: .cancel) {}
            Button(L10n.text("mac.backupSettingsView.body.fa5e198203"), role: .destructive) { deleteBackups() }
        } message: { Text(L10n.text("mac.backupSettingsView.body.82b9cba76e")) }
        .sheet(item: $nativeReview, onDismiss: presentPendingFeedback) { item in
            VStack(alignment: .leading, spacing: MacUI.space(18)) {
                Text(L10n.text("mac.backupSettingsView.body.10328a6f1a")).appFont(.dialogTitle, weight: .semibold).accessibilityIdentifier("nativeRestorePreviewTitle")
                Text(item.filename).appFont(.section, weight: .semibold)
                Text(L10n.format("mac.backupSettingsView.body.f14e588401", "\(MacDateDisplay.string(item.payload.createdAt))", "\(MacDisplayPreferences.time(item.payload.createdAt))"))
                Text(L10n.format("mac.backupSettingsView.body.57be9fb669", Int64(item.payload.transaction.count), Int64(item.payload.depositRecord.count), Int64(item.payload.loanRule.count), Int64(item.payload.recurringTransaction.count)))
                Text(L10n.format("mac.backupSettingsView.body.c995a9c7b5", Int64(item.payload.goal.count), Int64(item.payload.category.count), Int64(item.payload.financialProfile.count), Int64(item.payload.account.count)))
                Text(L10n.format("mac.backupSettingsView.body.43ff64334f", "\(item.payload.backupHistory?.count ?? 0)"))
                    .appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                updateTrustReview(item)
                Text(L10n.text("mac.backupSettingsView.body.ef44d6b603"))
                    .appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                if let notice = MacSettingsStore.restorationNotice(item.payload.settings) { Text(notice).foregroundStyle(.orange) }
                Text(L10n.text("mac.backupSettingsView.body.914ccfb54a")).foregroundStyle(.red)
                TextField(MacRestoreConfirmation.prompt, text: $restoreText).disabled(operation.status != nil).accessibilityIdentifier("nativeRestoreConfirmation")
                if let status=operation.status {ProgressView(status)}
                if let error { Text(error).foregroundStyle(.red) }
                HStack {
                    Button(L10n.text("mac.backupSettingsView.body.2cd0f3be87")) { nativeReview = nil }.keyboardShortcut(.cancelAction).disabled(operation.status != nil).accessibilityIdentifier("cancelNativeRestore")
                    Spacer()
                    Button(L10n.text("mac.backupSettingsView.body.5d0e2633e6"), role: .destructive) { restore(item) }.disabled(!MacRestoreConfirmation.accepts(restoreText) || operation.status != nil).accessibilityIdentifier("commitNativeRestore")
                }
            }.appPadding(28).appDialog(width: 570).interactiveDismissDisabled(operation.status != nil)
                .modifier(MacOperationFeedbackPresenter(center:feedback,location:.nativePreview))
        }
        .sheet(item: $csvReview, onDismiss: presentPendingFeedback) { item in
            VStack(alignment: .leading, spacing: MacUI.space(18)) {
                Text(L10n.text("mac.backupSettingsView.body.bd1f9c013d")).appFont(.dialogTitle, weight: .semibold).accessibilityIdentifier("csvImportReviewTitle")
                Text(item.filename)
                Text(L10n.format("mac.backupSettingsView.body.2a4b4ededb", "\(item.preview.kind?.title ?? L10n.text("mac.backupSettingsView.body.a57f0e55f6"))"))
                Text(L10n.format("mac.backupSettingsView.body.f4cf999704", Int64(item.preview.count)))
                Text(L10n.format("mac.backupSettingsView.body.edc87244a8", "\(item.preview.currencies.joined(separator: ", "))"))
                Text(item.preview.hasStableIDs ? L10n.text("mac.backupSettingsView.body.84aff541ed") : L10n.text("mac.backupSettingsView.body.055672cbbd"))
                    .appFont(.caption, weight: .regular).foregroundStyle(item.preview.hasStableIDs ? Color.secondary : .orange).accessibilityIdentifier("csvIdentityNotice")
                ScrollView {
                    VStack(alignment: .leading, spacing: MacUI.space(8)) {
                        ForEach(Array(item.preview.sections.keys.sorted()), id: \.self) { key in
                            if let table = item.preview.sections[key] {
                                Text(L10n.format("mac.backupSettingsView.ForEach.847c83d6c6", "\(table.sectionTitle)", Int64(table.rows.count))).appFont(.body, weight: .semibold)
                                ForEach(Array(table.rows.prefix(5).enumerated()), id: \.offset) { _, row in
                                    Text(csvRowSummary(row.values)).appFont(.caption, weight: .regular).textSelection(.enabled)
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: MacUI.space(200)).accessibilityIdentifier("csvPreviewRows")
                if let error { Text(error).foregroundStyle(.red) }
                HStack {
                    Button(L10n.text("mac.backupSettingsView.body.2cd0f3be87")) { csvReview = nil }.keyboardShortcut(.cancelAction)
                    Spacer(); Button(L10n.text("mac.backupSettingsView.body.4a8d6841b4")) {
                        do {
                            let wasEmpty = try context.fetchCount(FetchDescriptor<Transaction>()) == 0 && context.fetchCount(FetchDescriptor<LoanRule>()) == 0 && context.fetchCount(FetchDescriptor<DepositRecord>()) == 0 && context.fetchCount(FetchDescriptor<RecurringTransaction>()) == 0 && context.fetchCount(FetchDescriptor<Goal>()) == 0 && context.fetchCount(FetchDescriptor<FinancialProfile>()) == 0
                            if let currency = item.preview.standardBookCurrency {
                                guard try MacCurrency.ledgerCurrency(in: context, preferred: baseCurrency) == currency else { throw MacCSV.Failure.invalid(L10n.text("mac.backupSettingsView.body.cc7a1d3841")) }
                            }
                            let result = try MacCSV.commit(item.preview, in: context)
                            if wasEmpty && item.preview.currencies.count == 1 { baseCurrency = item.preview.currencies[0] }
                            message = L10n.format("mac.backupSettingsView.body.08c3109169", "\(result.totalRecordCount)"); error = nil; setup = true
                            pendingFeedback = .init(kind:result.totalRecordCount == 0 ? .warning : .success,
                                title:result.totalRecordCount == 0 ? L10n.text("mac.backupSettingsView.body.34046c4394") : L10n.text("mac.backupSettingsView.body.9911f5dcd8"),
                                message:L10n.format("mac.backupSettingsView.body.238ae08cf9", "\(item.filename)", "\(result.totalRecordCount)") + (result.totalRecordCount == 0 ? L10n.text("mac.backupSettingsView.body.67def97bdf") : ""))
                            csvReview = nil
                        } catch { reportFailure(L10n.text("mac.backupSettingsView.reportFailure.01aaebc96a"),error,location:.csvPreview) }
                    }.accessibilityIdentifier("commitCSVImport")
                }
            }.appPadding(26).appDialog(width: 540)
                .modifier(MacOperationFeedbackPresenter(center:feedback,location:.csvPreview))
        }
    }
    private func backupHistoryRow(_ record: MacBackupRecord) -> some View {
        VStack(alignment:.leading,spacing:8) {
            Label(record.name,systemImage:"doc.text").appFont(.body).lineLimit(2).truncationMode(.middle).frame(maxWidth:.infinity,alignment:.leading)
            ViewThatFits(in:.horizontal) {
                HStack {Text(MacDateDisplay.string(record.date)+" "+MacDisplayPreferences.time(record.date)).fixedSize();Spacer();Text(ByteCountFormatter.string(fromByteCount:Int64(record.size),countStyle:.file)).fixedSize()}
                VStack(alignment:.leading,spacing:5) {Text(MacDateDisplay.string(record.date)+" "+MacDisplayPreferences.time(record.date));Text(ByteCountFormatter.string(fromByteCount:Int64(record.size),countStyle:.file))}
            }.appFont(.caption).foregroundStyle(.secondary)
        }.padding(10).background(selectedBackups.contains(record.id) ? Color.blue.opacity(0.08):.clear,in:RoundedRectangle(cornerRadius:8)).contentShape(Rectangle()).appHelp(record.name)
    }
    private func presentPendingFeedback() {
        if let pendingFeedback { feedback.notice = pendingFeedback; self.pendingFeedback = nil }
    }
    private func reportFailure(_ title:String,_ failure:Error,location:MacOperationFeedbackCenter.Location = .workspace) {
        let detail = MacLocalization.error(failure)
        error = detail
        feedback.show(.failure,title:title,message:detail,location:location)
    }
    private func csvRowSummary(_ row: [String: String]) -> String {
        let title = row["Title"] ?? row["BankName"] ?? row["Category"] ?? ""
        let date = row["Date"] ?? row["StartDate"] ?? row["NextExecutionDate"] ?? ""
        let original = row["OriginalAmount"] ?? row["OriginalPrincipal"] ?? row["Principal"] ?? row["Amount"] ?? ""
        let base = row["BaseAmount"] ?? row["BasePrincipal"] ?? ""
        return L10n.format("mac.backupSettingsView.csvRowSummary.5bcfbb8e4a", "\(date)", "\(title)", "\(row["Type"] ?? "")", "\(original)", "\(row["OriginalCurrency"] ?? row["Currency"] ?? "")", "\(base)", "\(row["BaseCurrency"] ?? "")")
    }
    private func exportCSVTemplate() {
        do {
            let currency = try MacCurrency.ledgerCurrency(in: context, preferred: baseCurrency)
            let template = csvKind.blankTemplate(bookCurrency: currency)
            guard let url = savePanel(name: csvKind.templateName, type: .commaSeparatedText) else { return }
            try template.write(to: url, atomically: true, encoding: .utf8)
            message = L10n.format("mac.backupSettingsView.exportCSVTemplate.c8e150573a", "\(csvKind.title)"); error = nil
            feedback.show(.success,title:L10n.text("mac.backupSettingsView.exportCSVTemplate.5603e01058"),message:L10n.format("mac.backupSettingsView.exportCSVTemplate.c26aa02115", "\(url.lastPathComponent)"))
        } catch { reportFailure(L10n.text("mac.backupSettingsView.reportFailure.6e4445df69"),error) }
    }
    private func perform(_ label:String,failure:String,location:MacOperationFeedbackCenter.Location = .workspace,action:@escaping () async throws -> Void) {
        guard operation.status == nil else{return};operation.status=label
        Task {defer{operation.status=nil};do{try await action()}catch{reportFailure(failure,error,location:location)}}
    }
    private func exportTypedCSV() {
        let kind=csvKind
        guard let url=savePanel(name:kind.exportName,type:.commaSeparatedText) else{return}
        let range=exportRange == "全部时间" ? nil:Calendar.current.dateInterval(of:exportRange == "本月" ? .month:.year,for:Date())
        perform(L10n.text("mac.backupSettingsView.perform.55c44b8781"),failure:L10n.text("mac.backupSettingsView.perform.6e4445df69")) {
            let text=try await MacCSV.exportAsync(in:context,kind:kind,transactionRange:range)
            try await Task.detached(priority:.userInitiated){try MacDataIO.write(Data(text.utf8),to:url)}.value
            message=L10n.format("mac.backupSettingsView.perform.33821f027e", "\(kind.title)");error=nil
            feedback.show(.success,title:L10n.text("mac.backupSettingsView.perform.5603e01058"),message:L10n.format("mac.backupSettingsView.perform.8a26b234e5", "\(url.lastPathComponent)"))
        }
    }
    private func exportLegacyCSV() {
        guard let url=savePanel(name:"FinTrack_AllData.csv",type:.commaSeparatedText) else{return}
        perform(L10n.text("mac.backupSettingsView.perform.a110c729c2"),failure:L10n.text("mac.backupSettingsView.perform.6e4445df69")) {
            let text=try await MacCSV.exportAsync(in:context)
            try await Task.detached(priority:.userInitiated){try MacDataIO.write(Data(text.utf8),to:url)}.value
            message=L10n.text("mac.backupSettingsView.perform.5b08d9c34d");error=nil
            feedback.show(.success,title:L10n.text("mac.backupSettingsView.perform.5603e01058"),message:L10n.format("mac.backupSettingsView.perform.8a26b234e5", "\(url.lastPathComponent)"))
        }
    }
    private func savePanel(name: String, type: UTType) -> URL? {
        let panel = NSSavePanel(); panel.allowedContentTypes = [type]; panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        if !backupFolder.isEmpty { panel.directoryURL = URL(fileURLWithPath: backupFolder) }
        if MacPreferences.isTesting, let path = ProcessInfo.processInfo.environment["FINTRACK_TEST_CSV_FOLDER"], MacTestStore.isIsolated(URL(fileURLWithPath: path).appendingPathComponent("fixture.sqlite").path) { panel.directoryURL = URL(fileURLWithPath: path) }
        return panel.runModal() == .OK ? panel.url : nil
    }
    private var backupType: UTType { UTType(filenameExtension: "fintrack") ?? .data }
    private func openPanel(type: UTType) -> URL? {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [type]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        if MacPreferences.isTesting, let path = ProcessInfo.processInfo.environment["FINTRACK_TEST_CSV_FOLDER"], MacTestStore.isIsolated(URL(fileURLWithPath: path).appendingPathComponent("fixture.sqlite").path) { panel.directoryURL = URL(fileURLWithPath: path) }
        return panel.runModal() == .OK ? panel.url : nil
    }
    private func saveBackup(_ data:Data,at url:URL) async throws {
        _=try await MacNativeBackup.previewAsync(data)
        try await Task.detached(priority:.userInitiated){try MacDataIO.write(data,to:url)}.value
        try MacSettingsStore.save(MacBackupHistory.recording(data,at:url,history:history),key:"v2_backup_history")
        selectedBackups.removeAll()
    }
    private func createBackup() {
        let formatter=DateFormatter();formatter.dateFormat=naming == "date" ? "yyyyMMdd":"yyyyMMdd_HHmm"
        guard let url=savePanel(name:"FinTrack_backup_"+formatter.string(from:Date())+".fintrack",type:backupType) else{return}
        backupFolder=url.deletingLastPathComponent().path
        perform(L10n.text("mac.backupSettingsView.perform.f7307ac4cb"),failure:L10n.text("mac.backupSettingsView.perform.f3b4148926")) {
            let data=try await MacNativeBackup.createAsync(in:context)
            try await saveBackup(data,at:url);message=L10n.text("mac.backupSettingsView.perform.eab5315715");error=nil
            feedback.show(.success,title:L10n.text("mac.backupSettingsView.perform.8adf103c62"),message:L10n.format("mac.backupSettingsView.perform.76379836f1", "\(url.lastPathComponent)"))
        }
    }
    private func previewNative() {
        guard let url=openPanel(type:backupType) else{return}
        perform(L10n.text("mac.backupSettingsView.perform.7a1f32c750"),failure:L10n.text("mac.backupSettingsView.perform.4f33f9150b")) {
            let data=try await Task.detached(priority:.userInitiated){try MacDataIO.read(url)}.value
            let payload=try await MacNativeBackup.previewAsync(data)
            nativeReview=NativeReview(data:data,payload:payload,filename:url.lastPathComponent)
            restoreText="";includeUpdateTrust=false;error=nil
        }
    }
    private func restore(_ item:NativeReview) {
        let acceptedToken=MacRestoreConfirmation.token
        guard operation.status == nil, MacRestoreConfirmation.accepts(restoreText) else { return }
        guard let url=savePanel(name:L10n.format("mac.backupSettingsView.savePanel.c2f6fc6b30", "\(UUID().uuidString.prefix(8))"),type:backupType) else{return}
        guard restoreText == acceptedToken, MacRestoreConfirmation.token == acceptedToken else { return }
        let trust=includeUpdateTrust
        perform(L10n.text("mac.backupSettingsView.perform.7b19f301a1"),failure:L10n.text("mac.backupSettingsView.perform.89281a45e0"),location:.nativePreview) {
            let safety=try await MacNativeBackup.createAsync(in:context)
            try await saveBackup(safety,at:url)
            try MacDataOperationState.shared.commit {try MacNativeBackup.restore(item.data,in:context,restoreUpdateTrust:trust)}
            message=L10n.text("mac.backupSettingsView.perform.9b3bc05955");error=nil
            pendingFeedback = .init(kind:.success,title:L10n.text("mac.backupSettingsView.perform.9161dcfa6f"),message:L10n.text("mac.backupSettingsView.perform.d7881c80e7"))
            nativeReview=nil
        }
    }
    private func updateTrustReview(_ item: NativeReview) -> some View {
        Text(L10n.text("mac.backupSettingsView.updateTrustReview.49bb48dec6"))
            .appFont(.caption).foregroundStyle(.secondary)
    }
    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { backupFolder = url.path }
    }
    private func showFolder() {
        if let record = history.first(where: { selectedBackups.contains($0.id) && !$0.path.isEmpty }), FileManager.default.fileExists(atPath: record.path) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.path)]) }
        else if !backupFolder.isEmpty { NSWorkspace.shared.open(URL(fileURLWithPath: backupFolder)) }
        else { message = MacSettingsVisual.preview ? L10n.text("mac.backupSettingsView.showFolder.61d7543bbb") : L10n.text("mac.backupSettingsView.showFolder.812a083ba3") }
    }
    private func deleteBackups() {
        do {
            let updated = try MacBackupHistory.removing(selectedBackups, from: history)
            try MacSettingsStore.save(updated, key: "v2_backup_history"); selectedBackups.removeAll(); message = L10n.text("mac.backupSettingsView.deleteBackups.8216d1d33c"); error = nil
        } catch let failure as MacBackupHistory.PartialRemoval {
            do { try MacSettingsStore.save(failure.history, key: "v2_backup_history"); selectedBackups.removeAll() }
            catch { self.error = L10n.text("mac.backupSettingsView.deleteBackups.d7f87ec6b2") + error.localizedDescription; return }
            self.error = failure.localizedDescription
        } catch { self.error = MacLocalization.error(error) }
    }
    private func previewCSV(legacy:Bool=false) {
        guard let url=openPanel(type:.commaSeparatedText) else{return}
        let kind=legacy ? nil:csvKind,book=baseCurrency
        perform(L10n.text("mac.backupSettingsView.perform.4b71696c09"),failure:L10n.text("mac.backupSettingsView.perform.01aaebc96a")) {
            let data=try await Task.detached(priority:.userInitiated){try MacDataIO.read(url,limit:50_000_000)}.value
            guard let text=String(data:data,encoding:.utf8) else{throw MacSettingsFailure.invalid(L10n.text("mac.backupSettingsView.perform.fe8452ca20"))}
            let preview=try await MacCSV.previewAsync(text,bookCurrency:try MacCurrency.ledgerCurrency(in:context,preferred:book),kind:kind)
            csvReview=CSVReview(preview:preview,filename:url.lastPathComponent);error=nil
        }
    }
}
