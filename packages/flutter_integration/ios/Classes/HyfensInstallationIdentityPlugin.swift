import CommonCrypto
import CryptoKit
import Flutter
import Foundation
import Security

private struct KeyUnavailableError: Error {
  let message: String
  let underlying: Error?

  init(_ message: String, _ underlying: Error? = nil) {
    self.message = message
    self.underlying = underlying
  }
}

private struct KeychainStatusError: Error {
  let status: OSStatus
}

public class HyfensInstallationIdentityPlugin: NSObject, FlutterPlugin {
  private static let channelName = "hyfens/installation_identity"
  private static let keyTag = Data("dev.hyfens.hyfens_flutter_integration.installation.p256".utf8)
  private static let markerDirectory = "hyfens/installation_identity"
  private static let markerName = "installation.marker"
  private static let maxMessageLength = 16 * 1024
  // All engines in this app process share one Keychain item and marker.
  private static let queue = DispatchQueue(
    label: "dev.hyfens.hyfens_flutter_integration.installation_identity"
  )

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = HyfensInstallationIdentityPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getIdentity":
      Self.queue.async {
        do {
          result(try self.identityMap())
        } catch {
          result(Self.keyUnavailableError())
        }
      }
    case "sign":
      guard let message = HyfensInstallationIdentityCodec.messageData(call.arguments) else {
        result(
          FlutterError(
            code: "invalidMessage",
            message: "Signing message is not bytes.",
            details: nil
          )
        )
        return
      }
      guard message.count <= HyfensInstallationIdentityCodec.maxMessageLength else {
        result(
          FlutterError(
            code: "invalidMessage",
            message: "Signing message exceeds the 16 KiB limit.",
            details: nil
          )
        )
        return
      }
      Self.queue.async {
        do {
          result(try self.sign(message))
        } catch {
          result(Self.keyUnavailableError())
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func identityMap() throws -> [String: Any] {
    let record = try loadOrCreateRecord()
    return [
      "installationId": record.installationId,
      "keyId": record.keyId,
      "publicKey": FlutterStandardTypedData(bytes: record.publicKey),
      "storageProtection": record.storageProtection
    ]
  }

  private func sign(_ message: Data) throws -> FlutterStandardTypedData {
    let record = try loadOrCreateRecord()
    var error: Unmanaged<CFError>?
    guard let signature = SecKeyCreateSignature(
      record.privateKey,
      SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256,
      message as CFData,
      &error
    ) as Data? else {
      let failure = error?.takeRetainedValue().localizedDescription
        ?? "Could not sign with installation key"
      throw KeyUnavailableError(failure)
    }
    do {
      // CryptoKit validates the DER representation and exposes IEEE P1363
      // bytes; it does not create or export the private key.
      let p1363 = try P256.Signing.ECDSASignature(
        derRepresentation: signature
      ).rawRepresentation
      return FlutterStandardTypedData(bytes: p1363)
    } catch {
      throw KeyUnavailableError("Could not convert installation signature", error)
    }
  }

  private func loadOrCreateRecord() throws -> IdentityRecord {
    let marker = try readMarker()
    if marker == nil {
      try deleteKey()
      let privateKey = try generateKey()
      do {
        let publicKey = try publicKeyBytes(for: privateKey)
        let keyId = sha256Hex(publicKey)
        let installationId = try newInstallationId()
        let record = try makeRecord(
          installationId: installationId,
          keyId: keyId,
          publicKey: publicKey,
          privateKey: privateKey
        )
        try writeMarker(Marker(installationId: installationId, keyId: keyId))
        return record
      } catch {
        try? deleteKey()
        throw KeyUnavailableError("Could not persist installation identity", error)
      }
    }

    guard let marker = marker else {
      throw KeyUnavailableError("Installation marker is unavailable")
    }
    let privateKey = try existingKey()
    let publicKey = try publicKeyBytes(for: privateKey)
    let keyId = sha256Hex(publicKey)
    guard marker.keyId == keyId else {
      throw KeyUnavailableError("Installation key binding changed")
    }
    return try makeRecord(
      installationId: marker.installationId,
      keyId: keyId,
      publicKey: publicKey,
      privateKey: privateKey
    )
  }

  private func makeRecord(
    installationId: String,
    keyId: String,
    publicKey: Data,
    privateKey: SecKey
  ) throws -> IdentityRecord {
    guard publicKey.count == 65, publicKey.first == 0x04 else {
      throw KeyUnavailableError("Installation public key is not uncompressed P-256")
    }
    let protection = isSecureEnclaveKey(privateKey)
      ? "hardwareBacked"
      : "platformProtected"
    return IdentityRecord(
      installationId: installationId,
      keyId: keyId,
      publicKey: publicKey,
      storageProtection: protection,
      privateKey: privateKey
    )
  }

  private func existingKey() throws -> SecKey {
    var query = keyQuery()
    query[kSecReturnRef as String] = true
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let key = item else {
      throw KeyUnavailableError("Installation private key is missing")
    }
    guard CFGetTypeID(key) == SecKeyGetTypeID() else {
      throw KeyUnavailableError("Installation keychain item is not a key")
    }
    return unsafeBitCast(key, to: SecKey.self)
  }

  private func generateKey() throws -> SecKey {
    do {
      return try createKey(secureEnclave: true)
    } catch let error as KeychainStatusError where
        HyfensInstallationIdentityCodec.isSecureEnclaveUnavailable(error.status) {
      return try createKey(secureEnclave: false)
    } catch {
      throw error
    }
  }

  private func createKey(secureEnclave: Bool) throws -> SecKey {
    let privateAttributes: [String: Any] = [
      kSecAttrIsPermanent as String: true,
      kSecAttrApplicationTag as String: Self.keyTag,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      kSecAttrIsSensitive as String: true,
      kSecAttrIsExtractable as String: false
    ]
    var attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecPrivateKeyAttrs as String: privateAttributes
    ]
    if secureEnclave {
      attributes[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
    }
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
      let status: OSStatus
      if let error {
        status = OSStatus(CFErrorGetCode(error.takeRetainedValue()))
      } else {
        status = errSecParam
      }
      throw KeychainStatusError(status: status)
    }
    return key
  }

  private func deleteKey() throws {
    let status = SecItemDelete(keyQuery() as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainStatusError(status: status)
    }
  }

  private func keyQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassKey,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrApplicationTag as String: Self.keyTag
    ]
  }

  private func isSecureEnclaveKey(_ key: SecKey) -> Bool {
    guard let attributes = SecKeyCopyAttributes(key) as? [String: Any] else {
      return false
    }
    return (attributes[kSecAttrTokenID as String] as? String) ==
      (kSecAttrTokenIDSecureEnclave as String)
  }

  private func publicKeyBytes(for privateKey: SecKey) throws -> Data {
    guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
      throw KeyUnavailableError("Could not derive installation public key")
    }
    var error: Unmanaged<CFError>?
    guard let bytes = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
      let failure = error?.takeRetainedValue().localizedDescription
        ?? "Could not export installation public key"
      throw KeyUnavailableError(failure)
    }
    guard bytes.count == 65, bytes.first == 0x04 else {
      throw KeyUnavailableError("Installation public key is not uncompressed P-256")
    }
    return bytes
  }

  private func readMarker() throws -> Marker? {
    let file = markerURL()
    guard FileManager.default.fileExists(atPath: file.path) else { return nil }
    let contents: String
    do {
      contents = try String(contentsOf: file, encoding: .ascii)
    } catch {
      throw KeyUnavailableError("Could not read installation marker", error)
    }
    let parts = contents.split(separator: "\n", omittingEmptySubsequences: false)
    guard parts.count == 2 else {
      throw KeyUnavailableError("Installation marker is malformed")
    }
    let installationId = String(parts[0])
    let keyId = String(parts[1])
    guard HyfensInstallationIdentityCodec.isInstallationId(installationId),
          HyfensInstallationIdentityCodec.isKeyId(keyId) else {
      throw KeyUnavailableError("Installation marker is malformed")
    }
    return Marker(installationId: installationId, keyId: keyId)
  }

  private func writeMarker(_ marker: Marker) throws {
    let directory = markerURL().deletingLastPathComponent()
    do {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: nil
      )
      var directoryValues = URLResourceValues()
      directoryValues.isExcludedFromBackup = true
      var directoryURL = directory
      try directoryURL.setResourceValues(directoryValues)

      let file = markerURL()
      let temporary = file.appendingPathExtension("tmp")
      try Data(
        "\(marker.installationId)\n\(marker.keyId)".utf8
      ).write(to: temporary, options: .atomic)
      var fileValues = URLResourceValues()
      fileValues.isExcludedFromBackup = true
      var markerURL = temporary
      try markerURL.setResourceValues(fileValues)
      if FileManager.default.fileExists(atPath: file.path) {
        try FileManager.default.removeItem(at: file)
      }
      try FileManager.default.moveItem(at: temporary, to: file)
    } catch {
      throw KeyUnavailableError("Could not commit installation marker", error)
    }
  }

  private func markerURL() -> URL {
    let root = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    return root
      .appendingPathComponent(Self.markerDirectory, isDirectory: true)
      .appendingPathComponent(Self.markerName, isDirectory: false)
  }

  private func newInstallationId() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw KeyUnavailableError("Could not generate installation identity")
    }
    return Data(bytes)
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  private func sha256Hex(_ data: Data) -> String {
    var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { buffer in
      _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &digest)
    }
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  private static func keyUnavailableError() -> FlutterError {
    FlutterError(
      code: "keyUnavailable",
      message: "Installation identity is unavailable.",
      details: nil
    )
  }

  private struct Marker {
    let installationId: String
    let keyId: String
  }

  private struct IdentityRecord {
    let installationId: String
    let keyId: String
    let publicKey: Data
    let storageProtection: String
    let privateKey: SecKey
  }

}
