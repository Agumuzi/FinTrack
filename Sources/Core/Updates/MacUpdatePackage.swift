import Foundation
import CryptoKit

nonisolated enum MacUpdatePackageFailure: LocalizedError {
    case changed, format, structure, identity, preparation
    var errorDescription: String? {
        switch self {
        case .changed: "安装包内容已发生变化，请重新下载。"
        case .format: "此更新包格式不受支持，请从官网下载 DMG。"
        case .structure: "安装包结构不符合要求，现有应用未修改。"
        case .identity: "更新包身份或版本不匹配，现有应用未修改。"
        case .preparation: "更新包准备失败，现有应用未修改。"
        }
    }
}

/// File-only preparation, executed off the main actor. Never replaces an app.
nonisolated enum MacUpdatePackage {
    static func digest(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom:file); defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount:1024*1024), !data.isEmpty { hash.update(data:data) }
        return hash.finalize().map{String(format:"%02x",$0)}.joined()
    }
    static func prepare(_ archive: URL, release: MacUpdateRelease, bundleIdentifier: String) throws -> URL {
        guard try digest(archive) == release.sha256 else { throw MacUpdatePackageFailure.changed }
        let fm=FileManager.default, root=archive.deletingLastPathComponent()
        let extracted=root.appendingPathComponent("prepared-"+UUID().uuidString,isDirectory:true)
        try fm.createDirectory(at:extracted,withIntermediateDirectories:true)
        let candidate=extracted.appendingPathComponent("FinTrack.app",isDirectory:true)
        do {
            switch URL(string:release.packageURL)?.pathExtension.lowercased() {
            case "dmg":
                let mount=root.appendingPathComponent("mounted-"+UUID().uuidString,isDirectory:true)
                try fm.createDirectory(at:mount,withIntermediateDirectories:true)
                _ = try run("/usr/bin/hdiutil",["attach","-readonly","-nobrowse","-noautoopen","-mountpoint",mount.path,"-plist",archive.path])
                defer {
                    if (try? run("/usr/bin/hdiutil",["detach",mount.path])) == nil { _ = try? run("/usr/bin/hdiutil",["detach","-force",mount.path]) }
                    try? fm.removeItem(at:mount)
                }
                let source=mount.appendingPathComponent("FinTrack.app",isDirectory:true)
                let values=try source.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else { throw MacUpdatePackageFailure.structure }
                _ = try run("/usr/bin/ditto",[source.path,candidate.path])
            case "zip":
                let listing=try run("/usr/bin/unzip",["-Z1",archive.path])
                let entries=listing.split(separator:"\n").map(String.init)
                guard !entries.isEmpty,entries.count<=5000,entries.allSatisfy({!$0.hasPrefix("/") && !$0.split(separator:"/").contains("..") && ($0.hasPrefix("FinTrack.app/") || $0.hasPrefix("__MACOSX/"))}) else { throw MacUpdatePackageFailure.structure }
                _ = try run("/usr/bin/ditto",["-x","-k",archive.path,extracted.path])
            default: throw MacUpdatePackageFailure.format
            }
            _ = try run("/usr/bin/codesign",["--verify","--deep","--strict",candidate.path])
            let infoData=try Data(contentsOf:candidate.appendingPathComponent("Contents/Info.plist"))
            guard let info=try PropertyListSerialization.propertyList(from:infoData,format:nil) as? [String:Any],
                  info["CFBundleIdentifier"] as? String == bundleIdentifier,
                  String(describing:info["CFBundleVersion"] ?? "") == String(release.build),
                  info["CFBundleShortVersionString"] as? String == release.version else { throw MacUpdatePackageFailure.identity }
            return candidate
        } catch { try? fm.removeItem(at:extracted); throw error }
    }
    private static func run(_ executable: String,_ arguments: [String]) throws -> String {
        let process=Process();process.executableURL=URL(fileURLWithPath:executable);process.arguments=arguments
        let pipe=Pipe();process.standardOutput=pipe;process.standardError=FileHandle.nullDevice
        try process.run();let data=pipe.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
        guard process.terminationStatus==0 else { throw MacUpdatePackageFailure.preparation }
        return String(data:data,encoding:.utf8) ?? ""
    }
}
