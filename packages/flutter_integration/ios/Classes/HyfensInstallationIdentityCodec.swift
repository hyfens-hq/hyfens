import Flutter
import Foundation
import Security

enum HyfensInstallationIdentityCodec {
  static let maxMessageLength = 16 * 1024

  static func messageData(_ arguments: Any?) -> Data? {
    guard let arguments = arguments as? [String: Any],
          let value = arguments["message"] else { return nil }
    if let typed = value as? FlutterStandardTypedData { return typed.data }
    if let bytes = value as? [UInt8] { return Data(bytes) }
    if let integers = value as? [Int], integers.allSatisfy({ $0 >= 0 && $0 <= 255 }) {
      return Data(integers.map(UInt8.init))
    }
    return nil
  }

  static func isSecureEnclaveUnavailable(_ status: OSStatus) -> Bool {
    status == errSecNotAvailable || status == errSecParam || status == errSecUnimplemented
  }

  static func isInstallationId(_ value: String) -> Bool {
    guard value.count == 43,
          value.unicodeScalars.allSatisfy({
            ($0.value >= 65 && $0.value <= 90) ||
              ($0.value >= 97 && $0.value <= 122) ||
              ($0.value >= 48 && $0.value <= 57) ||
              $0.value == 45 || $0.value == 95
          }) else { return false }
    let normalized = value
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let padded = normalized + String(
      repeating: "=",
      count: (4 - normalized.count % 4) % 4
    )
    guard let data = Data(base64Encoded: padded) else {
      return false
    }
    let canonical = data
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    return data.count == 32 && canonical == value
  }

  static func isKeyId(_ value: String) -> Bool {
    value.count == 64 && value.unicodeScalars.allSatisfy {
      ($0.value >= 48 && $0.value <= 57) || ($0.value >= 97 && $0.value <= 102)
    }
  }
}
