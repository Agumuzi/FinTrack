import Foundation
import Combine

nonisolated enum MacDataIO {
    static func read(_ url: URL, limit: Int = 100*1024*1024) throws -> Data {
        let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
        guard let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<=limit else{throw MacSettingsFailure.invalid("文件超过允许的大小")}
        let data=try Data(contentsOf:url)
        guard data.count<=limit else{throw MacSettingsFailure.invalid("文件在读取时发生变化或超过大小限制")}
        return data
    }
    static func write(_ data: Data, to url: URL) throws {
        let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
        try data.write(to:url,options:.atomic)
        let saved=try Data(contentsOf:url)
        guard saved.count == data.count,MacNativeBackup.digest(saved)==MacNativeBackup.digest(data) else{throw MacSettingsFailure.invalid("文件写入校验失败")}
    }
}

@MainActor final class MacDataOperationState: ObservableObject {
    static let shared=MacDataOperationState()
    @Published var status: String?
    private(set) var committing=false
    func commit(_ body:() throws -> Void) rethrows {
        committing=true;defer{committing=false};try body()
    }
}
