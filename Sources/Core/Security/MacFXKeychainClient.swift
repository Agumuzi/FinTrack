import Foundation
import Security
import Darwin

/// Private pipe to the frozen keychain component. No key is passed in arguments,
/// written to a temporary file, or returned through a log/error description.
nonisolated enum MacFXKeychainClient {
    private struct Request: Encodable {
        let operation: String
        let account: String
        let value: String?
        let authorize: Bool
        let testKeychain: String?
    }
    private struct Response: Decodable { let status: Int32; let value: String? }
    static func perform(_ operation: String, id: UUID, value: String? = nil, authorize: Bool = false, testKeychain: String? = nil) throws -> (OSStatus, String?) {
        guard let url=Bundle.main.url(forResource:"FinTrackKeychainHelper",withExtension:nil) else {
            throw MacSettingsFailure.invalid("密钥服务不可用，请重新安装官方完整应用。")
        }
        var code:SecStaticCode?,requirement:SecRequirement?
        let rule="identifier \"dev.agumuzi.fintrack.fx.keychain-helper\" and certificate leaf = H\"51e58a1c399930d64ec957b3ae02489dd1e75c78\""
        guard SecStaticCodeCreateWithPath(url as CFURL,[],&code)==errSecSuccess,let code,
              SecRequirementCreateWithString(rule as CFString,[],&requirement)==errSecSuccess,let requirement,
              SecStaticCodeCheckValidity(code,SecCSFlags(rawValue:kSecCSStrictValidate),requirement)==errSecSuccess else {
            throw MacSettingsFailure.invalid("密钥服务签名验证失败，请重新安装官方完整应用。")
        }
        let input=try JSONEncoder().encode(Request(operation:operation,account:id.uuidString,value:value,authorize:authorize,testKeychain:testKeychain))
        guard input.count<=32768 else {throw MacSettingsFailure.invalid("API Key 过长。")}
        let output = try exchange(url, input: input, timeout: authorize ? 90 : 20)
        guard output.count<=32768,let response=try? JSONDecoder().decode(Response.self,from:output) else {
            throw MacSettingsFailure.invalid("密钥服务未能完成请求，请重试。")
        }
        return (response.status,response.value)
    }
    private static let queue = DispatchQueue(label: "dev.agumuzi.fintrack.keychain-ipc", qos: .userInitiated)
    static func performAsync(_ operation: String, id: UUID, value: String? = nil, authorize: Bool = false) async throws -> (OSStatus, String?) {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try perform(operation, id: id, value: value, authorize: authorize) }) }
        }
    }
    private final class Deadline: @unchecked Sendable {
        let lock = NSLock(); private var expired = false
        func expire() { lock.lock(); expired = true; lock.unlock() }
        var didExpire: Bool { lock.lock(); defer { lock.unlock() }; return expired }
    }
    static func exchange(_ executable: URL, arguments: [String] = [], input: Data, timeout: TimeInterval) throws -> Data {
        let process=Process(),write=Pipe(),read=Pipe(),deadline=Deadline()
        process.executableURL=executable;process.arguments=arguments
        process.standardInput=write;process.standardOutput=read;process.standardError=FileHandle.nullDevice
        try process.run()
        let timer=DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now()+timeout)
        timer.setEventHandler {
            if process.isRunning {
                deadline.expire();process.terminate()
                DispatchQueue.global().asyncAfter(deadline:.now()+0.2) {if process.isRunning {Darwin.kill(process.processIdentifier,SIGKILL)}}
            }
        }
        timer.resume();defer {timer.cancel()}
        try write.fileHandleForWriting.write(contentsOf: input);try write.fileHandleForWriting.close()
        let output=read.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
        guard !deadline.didExpire else {throw MacSettingsFailure.invalid("密钥服务响应超时，请重试。现有密钥不会被自动删除。")}
        return output
    }

}
