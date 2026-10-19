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
    var wide: Bool
    @Environment(\.modelContext) private var context
    @AppStorage("base_currency") private var baseCurrency = "USD"
    @AppStorage("fintrack_initial_setup_complete") private var setup = false
    @AppStorage("v2_backup_history") private var historyBytes = Data()
    @AppStorage("v2_backup_folder") private var backupFolder = ""
    @AppStorage("v2_backup_naming") private var naming = "datetime"
    @State private var selectedBackups = Set<UUID>()
    @State private var confirmDeleteBackups = false
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
    private var history: [MacBackupRecord] { (try? JSONDecoder().decode([MacBackupRecord].self, from: historyBytes)) ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.space(15)) {
            MacSettingsColumns(wide: wide) {
                VStack(spacing: MacUI.space(15)) {
                    MacSettingsCard(title: "数据备份", icon: "externaldrive.badge.plus", subtitle: "手动创建数据备份文件，建议定期备份。", headerColor: .blue, action: AnyView(Button("立即备份") { createBackup() }.buttonStyle(MacSettingsButtonStyle(primary: true)).accessibilityIdentifier("createNativeBackup"))) {
                        MacSettingsRow(label: "备份保存位置", labelWidth: 125) {
                            HStack(spacing: MacUI.space(8)) { Image(systemName: "folder.fill").foregroundStyle(.blue); Text(backupFolder.isEmpty ? (MacSettingsVisual.preview ? "~/FinTrack/Backups" : "保存时选择文件夹") : backupFolder.replacingOccurrences(of: NSHomeDirectory(), with: "~")).appFont(.caption, weight: .regular, design: .default).lineLimit(1).truncationMode(.middle); Spacer(minLength: 0); Button("更改…") { chooseFolder() } }
                        }
                        MacSettingsRow(label: "备份文件命名", labelWidth: 125) { MacSettingsMenu(selection: $naming, options: [("FinTrack_backup_YYYYMMDD_HHmm","datetime"), ("FinTrack_backup_YYYYMMDD","date")]).accessibilityIdentifier("backupNamingMenu") }
                        Text("完整备份包含账目、金融规则、预算、目标、可迁移设置和备份历史。更新源信任配置在恢复预览中单独选择。自定义 API Key 保存在系统钥匙串，不随备份导出；新设备需重新填写。")
                            .appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    MacSettingsCard(title: "备份记录", icon: "clock.arrow.circlepath", subtitle: "查看和管理已有的备份文件。", headerColor: .green) {
                        HStack { Text("文件名").frame(maxWidth: .infinity, alignment: .leading); Text("创建时间").frame(width: MacUI.space(104)); Text("大小").frame(width: MacUI.space(43)); Text("格式").frame(width: MacUI.space(32)) }.appFont(.caption, weight: .medium, design: .default).foregroundStyle(.secondary).appPadding(8).background(.gray.opacity(0.04))
                        VStack(spacing: MacUI.space(0)) {
                            if history.isEmpty { Text("尚未创建完整备份").appFont(.body, weight: .regular, design: .default).foregroundStyle(.secondary).appPadding(25) }
                            ForEach(history.prefix(8)) { record in
                                Button { if selectedBackups.contains(record.id) { selectedBackups.remove(record.id) } else { selectedBackups.insert(record.id) } } label: {
                                    HStack(spacing: MacUI.space(7)) { Image(systemName: "doc.text").appFont(.body, weight: .regular, design: .default); Text(record.name).appFont(.caption, weight: .medium, design: .default).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading); Text(MacDateDisplay.string(record.date) + "\n" + MacDisplayPreferences.time(record.date)).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).frame(width: MacUI.space(86)); Text(ByteCountFormatter.string(fromByteCount: Int64(record.size), countStyle: .file)).appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).frame(width: MacUI.space(44)); Text("1").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).frame(width: MacUI.space(28)) }.appPadding(.horizontal, 7).appMinHeight(41).background(selectedBackups.contains(record.id) ? Color.blue.opacity(0.08) : .clear).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Divider()
                            }
                        }
                        HStack { Button("在访达中显示备份文件夹", systemImage: "folder") { showFolder() }.appFont(.caption, weight: .regular, design: .default); Spacer(); Button("删除选中备份", role: .destructive) { confirmDeleteBackups = true }.disabled(selectedBackups.isEmpty).appFont(.caption, weight: .regular, design: .default) }
                    }
                    MacSettingsCard(title: "数据恢复", icon: "arrow.counterclockwise", subtitle: "从备份文件恢复数据。恢复将覆盖当前账本。", headerColor: .purple, action: AnyView(Button("选择备份文件…") { previewNative() }.accessibilityIdentifier("previewNativeRestore"))) {
                        Label("恢复会覆盖当前数据，请先保留安全副本。", systemImage: "exclamationmark.circle.fill").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.red).appPadding(12).frame(maxWidth: .infinity, alignment: .leading).background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            } right: {
                VStack(spacing: MacUI.space(15)) {
                    MacSettingsCard(title: "CSV 模板与导出", icon: "doc.badge.arrow.up", subtitle: "每类数据独立成表，便于 Excel 与 AI 整理。", headerColor: .orange) {
                        MacSettingsRow(label: "数据类型", labelWidth: 90) {
                            MacSettingsMenu(selection: Binding(get: { csvKind.rawValue }, set: { csvKind = MacCSVKind(rawValue: $0) ?? .transactions }), options: MacCSVKind.allCases.map { ($0.title, $0.rawValue) }).accessibilityIdentifier("csvDataKind")
                        }
                        if csvKind == .transactions {
                            MacSettingsRow(label: "账目时间范围", labelWidth: 100) { MacSettingsMenu(selection: $exportRange, options: [("全部时间", "全部时间"), ("本月", "本月"), ("本年", "本年")]).accessibilityIdentifier("backupExportRangeMenu") }
                        }
                        Button { exportCSVTemplate() } label: { Text("导出空白模板…").frame(maxWidth: .infinity) }.accessibilityIdentifier("exportCSVTemplate")
                        Button { exportTypedCSV() } label: { Text("导出\(csvKind.title)数据…").frame(maxWidth: .infinity) }.accessibilityIdentifier("exportCSVBackup")
                        Text("模板内已包含 AI 整理指令、字段规则和本位币。只需把原始账本与对应模板交给 AI，再导入整理后的 CSV。四类数据各自独立，模板说明不会计入记录。").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    MacSettingsCard(title: "导入数据", icon: "square.and.arrow.down", subtitle: "当前类型：\(csvKind.title)。先校验与预览，再确认合并。", headerColor: .green) {
                        Button { previewCSV() } label: { Text("选择\(csvKind.title) CSV…").frame(maxWidth: .infinity) }.accessibilityIdentifier("previewCSVImport")
                        Text("文件必须与上方类型一致；混合类型会被阻止。新周期规则默认暂停，导入不生成历史收据。建议先创建完整备份。").appFont(.caption, weight: .regular, design: .default).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        DisclosureGroup("旧版完整 CSV 兼容") {
                            Button("导出旧版完整 CSV…") { exportLegacyCSV() }.accessibilityIdentifier("exportLegacyCSV")
                            Button("导入旧版多分区 CSV…") { previewCSV(legacy: true) }.accessibilityIdentifier("previewLegacyCSVImport")
                            Text("用于导入本软件过去导出的完整 CSV；不用于 AI 新建数据。完整恢复请使用原生备份。").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                        }.appFont(.caption, weight: .regular)
                    }
                }
            }
            if let message { Text(message).appFont(.caption, weight: .regular).foregroundStyle(.green).accessibilityIdentifier("backupMessage") }
            if let error { Text(error).appFont(.caption, weight: .regular).foregroundStyle(.red).textSelection(.enabled).accessibilityIdentifier("backupError") }
        }
        .alert("删除选中的备份？", isPresented: $confirmDeleteBackups) {
            Button("取消", role: .cancel) {}
            Button("移到废纸篓", role: .destructive) { deleteBackups() }
        } message: { Text("只处理选中的备份文件，不修改账本；文件可从访达废纸篓恢复。") }
        .sheet(item: $nativeReview) { item in
            VStack(alignment: .leading, spacing: MacUI.space(18)) {
                Text("恢复预览").appFont(.dialogTitle, weight: .semibold).accessibilityIdentifier("nativeRestorePreviewTitle")
                Text(item.filename).appFont(.section, weight: .semibold)
                Text("备份时间：\(MacDateDisplay.string(item.payload.createdAt)) \(MacDisplayPreferences.time(item.payload.createdAt))")
                Text("账目 \(item.payload.transaction.count) · 存款 \(item.payload.depositRecord.count) · 贷款 \(item.payload.loanRule.count) · 周期 \(item.payload.recurringTransaction.count)")
                Text("目标 \(item.payload.goal.count) · 分类 \(item.payload.category.count) · 资产资料 \(item.payload.financialProfile.count) · 旧账户 \(item.payload.account.count)")
                Text("备份历史元数据：\(item.payload.backupHistory?.count ?? 0) 项；恢复后不会沿用旧设备文件路径。")
                    .appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                updateTrustReview(item)
                Text("系统钥匙串中的自定义汇率 API Key 不包含在备份中；恢复到新设备后需重新填写。")
                    .appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                if let notice = MacSettingsStore.restorationNotice(item.payload.settings) { Text(notice).foregroundStyle(.orange) }
                Text("当前账本将被覆盖。恢复后自动入账保持关闭。").foregroundStyle(.red)
                TextField("输入 恢复账本 进行确认", text: $restoreText).accessibilityIdentifier("nativeRestoreConfirmation")
                if let error { Text(error).foregroundStyle(.red) }
                HStack {
                    Button("取消") { nativeReview = nil }.keyboardShortcut(.cancelAction).accessibilityIdentifier("cancelNativeRestore")
                    Spacer()
                    Button("保存安全副本并恢复…", role: .destructive) { restore(item) }.disabled(restoreText != "恢复账本").accessibilityIdentifier("commitNativeRestore")
                }
            }.appPadding(28).appDialog(width: 570)
        }
        .sheet(item: $csvReview) { item in
            VStack(alignment: .leading, spacing: MacUI.space(18)) {
                Text("检查 CSV 导入").appFont(.dialogTitle, weight: .semibold).accessibilityIdentifier("csvImportReviewTitle")
                Text(item.filename)
                Text("数据类型：\(item.preview.kind?.title ?? "旧版完整数据")")
                Text("记录数量：\(item.preview.count)")
                Text("本位币：\(item.preview.currencies.joined(separator: ", "))")
                Text("原币金额、历史汇率与已保存收据保持原有导入规则。已有 ID 将跳过，不覆盖。").appFont(.caption, weight: .regular).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: MacUI.space(8)) {
                        ForEach(Array(item.preview.sections.keys.sorted()), id: \.self) { key in
                            if let table = item.preview.sections[key] {
                                Text("\(table.sectionTitle)：\(table.rows.count) 条").appFont(.body, weight: .semibold)
                                ForEach(Array(table.rows.prefix(5).enumerated()), id: \.offset) { _, row in
                                    Text(csvRowSummary(row.values)).appFont(.caption, weight: .regular).textSelection(.enabled)
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: MacUI.space(200)).accessibilityIdentifier("csvPreviewRows")
                if let error { Text(error).foregroundStyle(.red) }
                HStack {
                    Button("取消") { csvReview = nil }.keyboardShortcut(.cancelAction)
                    Spacer(); Button("确认导入") {
                        do {
                            let wasEmpty = try context.fetchCount(FetchDescriptor<Transaction>()) == 0 && context.fetchCount(FetchDescriptor<LoanRule>()) == 0 && context.fetchCount(FetchDescriptor<DepositRecord>()) == 0 && context.fetchCount(FetchDescriptor<RecurringTransaction>()) == 0 && context.fetchCount(FetchDescriptor<Goal>()) == 0 && context.fetchCount(FetchDescriptor<FinancialProfile>()) == 0
                            if let currency = item.preview.standardBookCurrency {
                                guard try MacCurrency.ledgerCurrency(in: context, preferred: baseCurrency) == currency else { throw MacCSV.Failure.invalid("本位币已改变，请重新选择CSV") }
                            }
                            let result = try MacCSV.commit(item.preview, in: context)
                            if wasEmpty && item.preview.currencies.count == 1 { baseCurrency = item.preview.currencies[0] }
                            message = "已导入 \(result.totalRecordCount) 条记录"; error = nil; setup = true; csvReview = nil
                        } catch { self.error = MacLocalization.error(error) }
                    }.accessibilityIdentifier("commitCSVImport")
                }
            }.appPadding(26).appDialog(width: 540)
        }
    }
    private func csvRowSummary(_ row: [String: String]) -> String {
        let title = row["Title"] ?? row["BankName"] ?? row["Category"] ?? ""
        let date = row["Date"] ?? row["StartDate"] ?? row["NextExecutionDate"] ?? ""
        let original = row["OriginalAmount"] ?? row["OriginalPrincipal"] ?? row["Principal"] ?? row["Amount"] ?? ""
        let base = row["BaseAmount"] ?? row["BasePrincipal"] ?? ""
        return "\(date) · \(title) · \(row["Type"] ?? "")\n原币 \(original) \(row["OriginalCurrency"] ?? row["Currency"] ?? "") → 本币 \(base) \(row["BaseCurrency"] ?? "")"
    }
    private func exportCSVTemplate() {
        do {
            let currency = try MacCurrency.ledgerCurrency(in: context, preferred: baseCurrency)
            let template = csvKind.blankTemplate(bookCurrency: currency)
            guard let url = savePanel(name: csvKind.templateName, type: .commaSeparatedText) else { return }
            try template.write(to: url, atomically: true, encoding: .utf8)
            message = "\(csvKind.title)空白模板已保存，文件内已包含 AI 指令与字段规范。"; error = nil
        } catch { self.error = MacLocalization.error(error) }
    }
    private func exportTypedCSV() {
        do {
            let range = exportRange == "全部时间" ? nil : Calendar.current.dateInterval(of: exportRange == "本月" ? .month : .year, for: Date())
            let text = try MacCSV.export(in: context, kind: csvKind, transactionRange: range)
            guard let url = savePanel(name: csvKind.exportName, type: .commaSeparatedText) else { return }
            try text.write(to: url, atomically: true, encoding: .utf8); message = "\(csvKind.title) CSV 已保存"; error = nil
        } catch { self.error = MacLocalization.error(error) }
    }
    private func exportLegacyCSV() {
        do {
            let temp = try MacCSV.export(in: context)
            defer { try? FileManager.default.removeItem(at: temp) }
            guard let url = savePanel(name: temp.lastPathComponent, type: .commaSeparatedText) else { return }
            try Data(contentsOf: temp).write(to: url, options: .atomic); message = "旧版完整 CSV 已保存"; error = nil
        } catch { self.error = MacLocalization.error(error) }
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
    private func read(_ url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 100 * 1024 * 1024 else { throw MacSettingsFailure.invalid("文件超过 100 MB") }
        return try Data(contentsOf: url)
    }
    private func saveBackup(_ data: Data, at url: URL) throws {
        _ = try MacNativeBackup.preview(data)
        try data.write(to: url, options: .atomic)
        let saved = try Data(contentsOf: url)
        guard MacNativeBackup.digest(saved) == MacNativeBackup.digest(data) else { throw MacSettingsFailure.invalid("备份写入校验失败") }
        var list = history
        list.insert(MacBackupRecord(name: url.lastPathComponent, path: url.path, date: Date(), size: saved.count, sha256: MacNativeBackup.digest(saved)), at: 0)
        try MacSettingsStore.save(Array(list.prefix(100)), key: "v2_backup_history")
    }
    private func createBackup() {
        do {
            let data = try MacNativeBackup.create(in: context)
            let formatter = DateFormatter(); formatter.dateFormat = naming == "date" ? "yyyyMMdd" : "yyyyMMdd_HHmm"
            guard let url = savePanel(name: "FinTrack_backup_" + formatter.string(from: Date()) + ".fintrack", type: backupType) else { return }
            backupFolder = url.deletingLastPathComponent().path
            try saveBackup(data, at: url); message = "完整备份已保存并校验"; error = nil
        } catch { self.error = MacLocalization.error(error) }
    }
    private func previewNative() {
        guard let url = openPanel(type: backupType) else { return }
        do { let data = try read(url); nativeReview = NativeReview(data: data, payload: try MacNativeBackup.preview(data), filename: url.lastPathComponent); restoreText = ""; includeUpdateTrust = false; error = nil }
        catch { self.error = "无法恢复：\(MacLocalization.error(error))" }
    }
    private func restore(_ item: NativeReview) {
        do {
            let safety = try MacNativeBackup.create(in: context)
            guard let url = savePanel(name: "FinTrack-恢复前-\(UUID().uuidString.prefix(8)).fintrack", type: backupType) else { return }
            try saveBackup(safety, at: url)
            try MacNativeBackup.restore(item.data, in: context, restoreUpdateTrust: includeUpdateTrust)
            nativeReview = nil; message = "账本已恢复；恢复前的安全副本已保留"; error = nil
        } catch { self.error = MacLocalization.error(error) }
    }
    @ViewBuilder
    private func updateTrustReview(_ item: NativeReview) -> some View {
        if let trust = item.payload.updateTrust {
            VStack(alignment: .leading, spacing: MacUI.space(8)) {
                Label("更新源信任配置", systemImage: "checkmark.shield").appFont(.body, weight: .semibold)
                Text(trust.url.isEmpty ? "未设置 HTTPS 更新清单地址" : trust.url)
                    .appFont(.caption, weight: .regular, design: .default).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if let fingerprint = trust.keyFingerprint {
                    Text("Ed25519 公钥指纹：\(fingerprint.prefix(20))…")
                        .appFont(.caption, weight: .regular, design: .monospaced).textSelection(.enabled)
                } else {
                    Text("备份未包含可读取的公钥指纹。")
                        .appFont(.caption, weight: .regular).foregroundStyle(.orange)
                }
                Toggle("恢复并信任此更新源配置", isOn: $includeUpdateTrust)
                    .disabled(!trust.isValid).accessibilityIdentifier("restoreUpdateTrust")
                Text(trust.isValid ? "默认保留当前设备的信任配置。勾选后会使用此 HTTPS 地址和 32 字节 Ed25519 公钥，并要求之后重新检查签名清单。" : "此更新源配置未通过 HTTPS 地址或公钥长度检查；账本仍可恢复，但不会应用该配置。")
                    .appFont(.caption, weight: .regular).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .appPadding(12).background(.gray.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        } else {
            Text("此旧备份没有更新源信任配置；当前设备的配置会保留。")
                .appFont(.caption, weight: .regular).foregroundStyle(.secondary)
        }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { backupFolder = url.path }
    }
    private func showFolder() {
        if let record = history.first(where: { selectedBackups.contains($0.id) && !$0.path.isEmpty }), FileManager.default.fileExists(atPath: record.path) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.path)]) }
        else if !backupFolder.isEmpty { NSWorkspace.shared.open(URL(fileURLWithPath: backupFolder)) }
        else { message = MacSettingsVisual.preview ? "当前为演示备份记录，创建真实备份后可在访达中查看。" : "请先选择备份文件夹或创建备份。" }
    }
    private func deleteBackups() {
        var removed = Set<UUID>()
        do {
            for record in history where selectedBackups.contains(record.id) {
                if !record.path.isEmpty, FileManager.default.fileExists(atPath: record.path) { try FileManager.default.trashItem(at: URL(fileURLWithPath: record.path), resultingItemURL: nil) }
                removed.insert(record.id)
            }
            try MacSettingsStore.save(history.filter { !removed.contains($0.id) }, key: "v2_backup_history"); selectedBackups.removeAll(); message = "选中的备份记录已移除"; error = nil
        } catch { self.error = MacLocalization.error(error) }
    }
    private func previewCSV(legacy: Bool = false) {
        guard let url = openPanel(type: .commaSeparatedText) else { return }
        do {
            let data = try read(url)
            guard data.count <= 50_000_000, let text = String(data: data, encoding: .utf8) else { throw MacSettingsFailure.invalid("请选择不超过 50,000,000 字节的 UTF-8 CSV") }
            csvReview = CSVReview(preview: try MacCSV.preview(text, bookCurrency: try MacCurrency.ledgerCurrency(in: context, preferred: baseCurrency), kind: legacy ? nil : csvKind), filename: url.lastPathComponent); error = nil
        } catch { self.error = MacLocalization.error(error) }
    }
}
