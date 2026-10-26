import Foundation
import Security
import Darwin

// This component has its own version and frozen signed executable. Ordinary
// FinTrack releases reuse it byte for byte, preserving the keychain partition.
struct Request: Decodable {
    let operation: String
    let account: String
    let value: String?
    let authorize: Bool
    let testKeychain: String?
}
struct Response: Encodable { let status: Int32; let value: String? }
let appRequirement = "identifier \"dev.agumuzi.fintrack.macos\" and certificate leaf = H\"51e58a1c399930d64ec957b3ae02489dd1e75c78\""
func authorizedParent() -> Bool {
    let pid = getppid()
    guard pid > 1 else { return false }
    var code: SecCode?, requirement: SecRequirement?
    guard SecCodeCopyGuestWithAttributes(nil,[kSecGuestAttributePid as String:pid] as CFDictionary,[],&code)==errSecSuccess,
          let code, SecRequirementCreateWithString(appRequirement as CFString,[],&requirement)==errSecSuccess,let requirement else { return false }
    return SecCodeCheckValidity(code,SecCSFlags(rawValue:kSecCSStrictValidate),requirement)==errSecSuccess
}
func reply(_ status: OSStatus, _ value: String? = nil) -> Never {
    if let data=try? JSONEncoder().encode(Response(status:status,value:value)) {FileHandle.standardOutput.write(data)}
    exit(status == errSecSuccess ? 0 : 1)
}
guard authorizedParent() else { reply(errSecAuthFailed) }
let input=FileHandle.standardInput.readDataToEndOfFile()
guard input.count<=32768,let request=try? JSONDecoder().decode(Request.self,from:input),
      UUID(uuidString:request.account) != nil,["read","save","delete"].contains(request.operation),
      (request.value?.utf8.count ?? 0)<=8192 else {reply(errSecParam)}
var query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"dev.agumuzi.fintrack.fx",kSecAttrAccount as String:request.account,
    kSecUseAuthenticationUI as String:request.authorize ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail]
var isolated:SecKeychain?
if let path=request.testKeychain {
    // Explicit synthetic fixtures only; a caller can never name login.keychain.
    let url=URL(fileURLWithPath:path).standardizedFileURL.resolvingSymlinksInPath()
    let directory=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Keychains").standardizedFileURL.resolvingSymlinksInPath()
    guard url.deletingLastPathComponent()==directory,url.lastPathComponent.hasPrefix("FinTrack-V13-keychain-"),
          url.pathExtension=="keychain" || url.pathExtension=="keychain-db",
          SecKeychainOpen(path,&isolated)==errSecSuccess,let isolated else {reply(errSecParam)}
    query[kSecMatchSearchList as String]=[isolated]
    SecKeychainSetUserInteractionAllowed(false)
}
switch request.operation {
case "read":
    query[kSecReturnData as String]=true;query[kSecMatchLimit as String]=kSecMatchLimitOne
    var value:CFTypeRef?;let status=SecItemCopyMatching(query as CFDictionary,&value)
    guard status==errSecSuccess else {reply(status)}
    guard let data=value as? Data,let string=String(data:data,encoding:.utf8) else {reply(errSecDecode)}
    reply(status,string)
case "save":
    guard let value=request.value else {reply(errSecParam)}
    let attributes=[kSecValueData as String:Data(value.utf8)]
    var status=SecItemUpdate(query as CFDictionary,attributes as CFDictionary)
    if status==errSecItemNotFound {
        query.removeValue(forKey:kSecMatchSearchList as String)
        if let isolated {query[kSecUseKeychain as String]=isolated}
        query[kSecValueData as String]=Data(value.utf8)
        status=SecItemAdd(query as CFDictionary,nil)
    }
    reply(status)
case "delete":reply(SecItemDelete(query as CFDictionary))
default:reply(errSecParam)
}
