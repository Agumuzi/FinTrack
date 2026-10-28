import Foundation
import Combine

nonisolated enum MacDataIO {
    static func read(_ url: URL, limit: Int = 100*1024*1024) throws -> Data {
        let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
        let properties=try url.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey])
        guard limit>0,limit<Int.max,properties.isRegularFile == true,let size=properties.fileSize,size<=limit else{throw MacSettingsFailure.invalid("文件类型无效或超过允许的大小")}
        let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
        var data=Data()
        while let chunk=try handle.read(upToCount:min(64*1024,limit-data.count+1)),!chunk.isEmpty {
            guard chunk.count<=limit-data.count else{throw MacSettingsFailure.invalid("文件在读取时发生变化或超过大小限制")}
            data.append(chunk)
        }
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
