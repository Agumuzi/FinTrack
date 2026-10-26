import Foundation
import Security

/// Private pipe to the frozen keychain component. No key is passed in arguments,
/// written to a temporary file, or returned through a log/error description.
enum MacFXKeychainClient {
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
        let process=Process(),write=Pipe(),read=Pipe()
        process.executableURL=url;process.standardInput=write;process.standardOutput=read;process.standardError=FileHandle.nullDevice
        try process.run()
        write.fileHandleForWriting.write(input);try write.fileHandleForWriting.close()
        let output=read.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
        guard output.count<=32768,let response=try? JSONDecoder().decode(Response.self,from:output) else {
            throw MacSettingsFailure.invalid("密钥服务未能完成请求，请重试。")
        }
        return (response.status,response.value)
    }
}
