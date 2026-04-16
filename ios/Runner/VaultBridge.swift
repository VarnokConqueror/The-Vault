import Flutter
import Foundation
import LibSignalClient

final class VaultBridge {
  static let channelName = "the_vault/vault"
  private static let shared = VaultBridge()

  private let defaults = UserDefaults.standard
  private let context = NullContext()
  private let fingerprintGenerator = NumericFingerprintGenerator(
    iterations: VaultConstants.fingerprintIterations
  )

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler(shared.handle)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      let arguments = try requireArguments(call)
      switch call.method {
      case "getOrCreateIdentity":
        let userId = try requireString(arguments, key: "userId")
        let deviceId = try requireInt(arguments, key: "deviceId")
        let state = try getOrCreateIdentity(userId: userId, deviceId: deviceId)
        result(identityPayload(state))
      case "generatePreKeyUpload":
        let userId = try requireString(arguments, key: "userId")
        let deviceId = try requireInt(arguments, key: "deviceId")
        let oneTimePreKeyCount = try requireInt(arguments, key: "oneTimePreKeyCount")
        let state = try getOrCreateIdentity(userId: userId, deviceId: deviceId)
        result(try generatePreKeyUpload(state: state, oneTimePreKeyCount: oneTimePreKeyCount))
      case "processPreKeyBundle":
        try handleProcessPreKeyBundle(arguments: arguments)
        result(nil)
      case "encrypt":
        result(try handleEncrypt(arguments: arguments))
      case "decrypt":
        result(try handleDecrypt(arguments: arguments))
      case "archiveSession":
        try handleArchiveSession(arguments: arguments)
        result(nil)
      case "generateFingerprint":
        result(try handleGenerateFingerprint(arguments: arguments))
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch let error as VaultBridgeError {
      result(error.flutterError)
    } catch let error as SignalError {
      result(mapSignalError(error))
    } catch {
      result(
        FlutterError(
          code: "vault_bridge_error",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  private func getOrCreateIdentity(userId: String, deviceId: Int) throws -> LocalIdentityState {
    let storagePrefix = prefix(userId: userId, deviceId: deviceId)
    if let serializedIdentity = defaults.string(forKey: "\(storagePrefix):identityKeyPair"),
       let registrationId = defaults.object(forKey: "\(storagePrefix):registrationId") as? NSNumber,
       registrationId.intValue > 0 {
      return try LocalIdentityState(
        userId: userId,
        deviceId: deviceId,
        registrationId: registrationId.intValue,
        identityKeyPair: IdentityKeyPair(bytes: dataFromBase64(serializedIdentity))
      )
    }

    let identityKeyPair = IdentityKeyPair.generate()
    let generatedRegistrationId = Int(UInt32.random(in: 1...0x3FFF))
    defaults.set(toBase64(identityKeyPair.serialize()), forKey: "\(storagePrefix):identityKeyPair")
    defaults.set(generatedRegistrationId, forKey: "\(storagePrefix):registrationId")
    defaults.set(1, forKey: "\(storagePrefix):nextPreKeyId")
    defaults.set(1, forKey: "\(storagePrefix):nextSignedPreKeyId")
    defaults.set(1, forKey: "\(storagePrefix):nextKyberPreKeyId")

    return LocalIdentityState(
      userId: userId,
      deviceId: deviceId,
      registrationId: generatedRegistrationId,
      identityKeyPair: identityKeyPair
    )
  }

  private func generatePreKeyUpload(
    state: LocalIdentityState,
    oneTimePreKeyCount: Int
  ) throws -> [String: Any] {
    let storagePrefix = prefix(userId: state.userId, deviceId: state.deviceId)
    let generatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)

    let signedPreKeyId = allocateNextId(prefix: storagePrefix, counterName: "nextSignedPreKeyId")
    let signedPreKeyPrivate = PrivateKey.generate()
    let signedPreKeySignature = state.identityKeyPair.privateKey.generateSignature(
      message: signedPreKeyPrivate.publicKey.serialize()
    )
    let signedPreKeyRecord = try SignedPreKeyRecord(
      id: UInt32(signedPreKeyId),
      timestamp: UInt64(generatedAtMs),
      privateKey: signedPreKeyPrivate,
      signature: signedPreKeySignature
    )
    storeRecord(
      prefKey: "\(storagePrefix):signedPreKeyRecords",
      recordId: signedPreKeyId,
      serializedRecord: signedPreKeyRecord.serialize()
    )

    let kyberPreKeyId = allocateNextId(prefix: storagePrefix, counterName: "nextKyberPreKeyId")
    let kyberPreKeyPair = KEMKeyPair.generate()
    let kyberPreKeySignature = state.identityKeyPair.privateKey.generateSignature(
      message: kyberPreKeyPair.publicKey.serialize()
    )
    let kyberPreKeyRecord = try KyberPreKeyRecord(
      id: UInt32(kyberPreKeyId),
      timestamp: UInt64(generatedAtMs),
      keyPair: kyberPreKeyPair,
      signature: kyberPreKeySignature
    )
    storeRecord(
      prefKey: "\(storagePrefix):kyberPreKeyRecords",
      recordId: kyberPreKeyId,
      serializedRecord: kyberPreKeyRecord.serialize()
    )

    let oneTimePreKeys = try allocateNextIds(
      prefix: storagePrefix,
      counterName: "nextPreKeyId",
      count: max(oneTimePreKeyCount, 0)
    ).map { preKeyId in
      let preKeyPrivate = PrivateKey.generate()
      let preKeyRecord = try PreKeyRecord(id: UInt32(preKeyId), privateKey: preKeyPrivate)
      storeRecord(
        prefKey: "\(storagePrefix):oneTimePreKeyRecords",
        recordId: preKeyId,
        serializedRecord: preKeyRecord.serialize()
      )
      return [
        "keyId": preKeyId,
        "publicKeyB64": toBase64(preKeyPrivate.publicKey.serialize()),
      ]
    }

    return [
      "identity": identityPayload(state),
      "signedPreKey": [
        "keyId": signedPreKeyId,
        "publicKeyB64": toBase64(signedPreKeyPrivate.publicKey.serialize()),
        "signatureB64": toBase64(signedPreKeySignature),
        "generatedAtMs": generatedAtMs,
      ],
      "kyberPreKey": [
        "keyId": kyberPreKeyId,
        "publicKeyB64": toBase64(kyberPreKeyPair.publicKey.serialize()),
        "signatureB64": toBase64(kyberPreKeySignature),
        "generatedAtMs": generatedAtMs,
      ],
      "oneTimePreKeys": oneTimePreKeys,
    ]
  }

  private func identityPayload(_ state: LocalIdentityState) -> [String: Any] {
    [
      "address": addressPayload(userId: state.userId, deviceId: state.deviceId),
      "registrationId": state.registrationId,
      "identityPublicKeyB64": toBase64(state.identityKeyPair.identityKey.serialize()),
    ]
  }

  private func addressPayload(userId: String, deviceId: Int) -> [String: Any] {
    [
      "userId": userId,
      "deviceId": deviceId,
    ]
  }

  private func allocateNextId(prefix: String, counterName: String) -> Int {
    let key = "\(prefix):\(counterName)"
    let nextId = defaults.integer(forKey: key) == 0 ? 1 : defaults.integer(forKey: key)
    defaults.set(nextId + 1, forKey: key)
    return nextId
  }

  private func allocateNextIds(prefix: String, counterName: String, count: Int) throws -> [Int] {
    guard count > 0 else {
      return []
    }
    let key = "\(prefix):\(counterName)"
    let nextId = defaults.integer(forKey: key) == 0 ? 1 : defaults.integer(forKey: key)
    defaults.set(nextId + count, forKey: key)
    return Array(nextId..<(nextId + count))
  }

  private func storeRecord(prefKey: String, recordId: Int, serializedRecord: Data) {
    var records = loadStringMap(prefKey)
    records[String(recordId)] = toBase64(serializedRecord)
    saveStringMap(prefKey, values: records)
  }

  // MARK: Transport handlers
  private func handleProcessPreKeyBundle(arguments: [String: Any]) throws {
    let localAddress = try requireAddress(arguments, key: "localAddress")
    let bundle = try requireBundle(arguments)
    let state = try getOrCreateIdentity(
      userId: localAddress.userId,
      deviceId: localAddress.deviceId
    )
    let storeHolder = PersistedVaultStore(
      defaults: defaults,
      context: context,
      state: state
    )
    let store = try storeHolder.load()
    let remoteAddress = try bundle.address.toProtocolAddress()
    let identityKey = try IdentityKey(bytes: dataFromBase64(bundle.identityPublicKeyB64))
    let signedPreKeyPublic = try PublicKey(dataFromBase64(bundle.signedPreKey.publicKeyB64))
    let kyberPreKeyPublic = try KEMPublicKey(dataFromBase64(bundle.kyberPreKey.publicKeyB64))
    let preKeyBundle: PreKeyBundle
    if let oneTimePreKey = bundle.oneTimePreKey {
      preKeyBundle = try PreKeyBundle(
        registrationId: UInt32(bundle.registrationId),
        deviceId: UInt32(bundle.address.deviceId),
        prekeyId: UInt32(oneTimePreKey.keyId),
        prekey: try PublicKey(dataFromBase64(oneTimePreKey.publicKeyB64)),
        signedPrekeyId: UInt32(bundle.signedPreKey.keyId),
        signedPrekey: signedPreKeyPublic,
        signedPrekeySignature: dataFromBase64(bundle.signedPreKey.signatureB64),
        identity: identityKey,
        kyberPrekeyId: UInt32(bundle.kyberPreKey.keyId),
        kyberPrekey: kyberPreKeyPublic,
        kyberPrekeySignature: dataFromBase64(bundle.kyberPreKey.signatureB64)
      )
    } else {
      preKeyBundle = try PreKeyBundle(
        registrationId: UInt32(bundle.registrationId),
        deviceId: UInt32(bundle.address.deviceId),
        signedPrekeyId: UInt32(bundle.signedPreKey.keyId),
        signedPrekey: signedPreKeyPublic,
        signedPrekeySignature: dataFromBase64(bundle.signedPreKey.signatureB64),
        identity: identityKey,
        kyberPrekeyId: UInt32(bundle.kyberPreKey.keyId),
        kyberPrekey: kyberPreKeyPublic,
        kyberPrekeySignature: dataFromBase64(bundle.kyberPreKey.signatureB64)
      )
    }
    try processPreKeyBundle(
      preKeyBundle,
      for: remoteAddress,
      sessionStore: store,
      identityStore: store,
      context: context
    )
    try storeHolder.persist(store: store, touchedAddresses: [remoteAddress])
  }

  private func handleEncrypt(arguments: [String: Any]) throws -> [String: Any] {
    let localAddress = try requireAddress(arguments, key: "localAddress")
    let destination = try requireAddress(arguments, key: "destination")
    let plaintext = try requireData(arguments, key: "plaintext")
    let state = try getOrCreateIdentity(
      userId: localAddress.userId,
      deviceId: localAddress.deviceId
    )
    let storeHolder = PersistedVaultStore(
      defaults: defaults,
      context: context,
      state: state
    )
    let store = try storeHolder.load()
    let localProtocolAddress = try localAddress.toProtocolAddress()
    let remoteProtocolAddress = try destination.toProtocolAddress()
    let ciphertext = try signalEncrypt(
      message: plaintext,
      for: remoteProtocolAddress,
      localAddress: localProtocolAddress,
      sessionStore: store,
      identityStore: store,
      context: context
    )
    try storeHolder.persist(store: store, touchedAddresses: [remoteProtocolAddress])
    return [
      "messageType": messageTypeName(ciphertext.messageType),
      "ciphertextB64": toBase64(ciphertext.serialize()),
    ]
  }

  private func handleDecrypt(arguments: [String: Any]) throws -> [Int] {
    let localAddress = try requireAddress(arguments, key: "localAddress")
    let envelope = try requireEnvelope(arguments)
    let state = try getOrCreateIdentity(
      userId: localAddress.userId,
      deviceId: localAddress.deviceId
    )
    let storeHolder = PersistedVaultStore(
      defaults: defaults,
      context: context,
      state: state
    )
    let store = try storeHolder.load()
    let localProtocolAddress = try localAddress.toProtocolAddress()
    let remoteProtocolAddress = try envelope.source.toProtocolAddress()
    let serializedCiphertext = try dataFromBase64(envelope.ciphertextB64)
    let plaintext: Data
    switch try messageTypeCode(envelope.messageType) {
    case .preKey:
      plaintext = try signalDecryptPreKey(
        message: PreKeySignalMessage(bytes: serializedCiphertext),
        from: remoteProtocolAddress,
        localAddress: localProtocolAddress,
        sessionStore: store,
        identityStore: store,
        preKeyStore: store,
        signedPreKeyStore: store,
        kyberPreKeyStore: store,
        context: context
      )
    case .whisper:
      plaintext = try signalDecrypt(
        message: SignalMessage(bytes: serializedCiphertext),
        from: remoteProtocolAddress,
        sessionStore: store,
        identityStore: store,
        context: context
      )
    }
    try storeHolder.persist(store: store, touchedAddresses: [remoteProtocolAddress])
    return Array(plaintext).map(Int.init)
  }

  private func handleArchiveSession(arguments: [String: Any]) throws {
    let localAddress = try requireAddress(arguments, key: "localAddress")
    let remoteAddress = try requireAddress(arguments, key: "remoteAddress")
    let state = try getOrCreateIdentity(
      userId: localAddress.userId,
      deviceId: localAddress.deviceId
    )
    let storeHolder = PersistedVaultStore(
      defaults: defaults,
      context: context,
      state: state
    )
    let store = try storeHolder.load()
    let remoteProtocolAddress = try remoteAddress.toProtocolAddress()
    if let session = try store.loadSession(for: remoteProtocolAddress, context: context) {
      session.archiveCurrentState()
      try store.storeSession(session, for: remoteProtocolAddress, context: context)
    }
    try storeHolder.persist(store: store, touchedAddresses: [remoteProtocolAddress])
  }

  private func handleGenerateFingerprint(arguments: [String: Any]) throws -> [String: Any] {
    let localAddress = try requireAddress(arguments, key: "localAddress")
    let remoteIdentity = try requireDeviceIdentity(arguments, key: "remoteIdentity")
    let state = try getOrCreateIdentity(
      userId: localAddress.userId,
      deviceId: localAddress.deviceId
    )
    let remoteIdentityKeyBytes = try dataFromBase64(remoteIdentity.identityPublicKeyB64)
    let remoteIdentityKey = try PublicKey(remoteIdentityKeyBytes)
    let fingerprint = try fingerprintGenerator.create(
      version: VaultConstants.fingerprintVersion,
      localIdentifier: Data(localAddress.userId.utf8),
      localKey: state.identityKeyPair.identityKey.publicKey,
      remoteIdentifier: Data(remoteIdentity.address.userId.utf8),
      remoteKey: remoteIdentityKey
    )
    return [
      "displayable": fingerprint.displayable.formatted,
      "scannableFingerprintB64": toBase64(fingerprint.scannable.encoding),
    ]
  }

  // MARK: Parsing
  private func requireArguments(_ call: FlutterMethodCall) throws -> [String: Any] {
    guard let raw = call.arguments as? [AnyHashable: Any] else {
      throw VaultBridgeError.invalidArgument("arguments are required")
    }
    return dictionaryFrom(raw)
  }

  private func requireAddress(_ payload: [String: Any], key: String) throws -> VaultAddressArg {
    try parseAddress(requireMap(payload, key: key))
  }

  private func requireBundle(_ payload: [String: Any]) throws -> VaultPreKeyBundleArg {
    let bundle = try requireMap(payload, key: "bundle")
    let oneTimePreKey = optionalMap(bundle, key: "oneTimePreKey")
    return VaultPreKeyBundleArg(
      address: try parseAddress(requireMap(bundle, key: "address")),
      registrationId: try requireInt(bundle, key: "registrationId"),
      identityPublicKeyB64: try requireString(bundle, key: "identityPublicKeyB64"),
      signedPreKey: try parseSignedPreKey(requireMap(bundle, key: "signedPreKey")),
      kyberPreKey: try parseKyberPreKey(requireMap(bundle, key: "kyberPreKey")),
      oneTimePreKey: try oneTimePreKey.map(parseOneTimePreKey)
    )
  }

  private func requireEnvelope(_ payload: [String: Any]) throws -> VaultInboundEnvelopeArg {
    let envelope = try requireMap(payload, key: "envelope")
    let ciphertext = try requireMap(envelope, key: "ciphertext")
    return VaultInboundEnvelopeArg(
      source: try parseAddress(requireMap(envelope, key: "source")),
      messageType: try requireString(ciphertext, key: "messageType"),
      ciphertextB64: try requireString(ciphertext, key: "ciphertextB64")
    )
  }

  private func requireDeviceIdentity(
    _ payload: [String: Any],
    key: String
  ) throws -> VaultDeviceIdentityArg {
    let identity = try requireMap(payload, key: key)
    return VaultDeviceIdentityArg(
      address: try parseAddress(requireMap(identity, key: "address")),
      registrationId: try requireInt(identity, key: "registrationId"),
      identityPublicKeyB64: try requireString(identity, key: "identityPublicKeyB64")
    )
  }

  private func parseAddress(_ payload: [String: Any]) throws -> VaultAddressArg {
    VaultAddressArg(
      userId: try requireString(payload, key: "userId"),
      deviceId: try requireInt(payload, key: "deviceId")
    )
  }

  private func parseSignedPreKey(_ payload: [String: Any]) throws -> VaultSignedPreKeyArg {
    VaultSignedPreKeyArg(
      keyId: try requireInt(payload, key: "keyId"),
      publicKeyB64: try requireString(payload, key: "publicKeyB64"),
      signatureB64: try requireString(payload, key: "signatureB64"),
      generatedAtMs: try requireInt64(payload, key: "generatedAtMs")
    )
  }

  private func parseKyberPreKey(_ payload: [String: Any]) throws -> VaultKyberPreKeyArg {
    VaultKyberPreKeyArg(
      keyId: try requireInt(payload, key: "keyId"),
      publicKeyB64: try requireString(payload, key: "publicKeyB64"),
      signatureB64: try requireString(payload, key: "signatureB64"),
      generatedAtMs: try requireInt64(payload, key: "generatedAtMs")
    )
  }

  private func parseOneTimePreKey(_ payload: [String: Any]) throws -> VaultOneTimePreKeyArg {
    VaultOneTimePreKeyArg(
      keyId: try requireInt(payload, key: "keyId"),
      publicKeyB64: try requireString(payload, key: "publicKeyB64")
    )
  }

  private func requireMap(_ payload: [String: Any], key: String) throws -> [String: Any] {
    if let map = payload[key] as? [String: Any] {
      return map
    }
    if let map = payload[key] as? [AnyHashable: Any] {
      return dictionaryFrom(map)
    }
    throw VaultBridgeError.invalidArgument("\(key) is required")
  }

  private func optionalMap(_ payload: [String: Any], key: String) -> [String: Any]? {
    if let map = payload[key] as? [String: Any] {
      return map
    }
    if let map = payload[key] as? [AnyHashable: Any] {
      return dictionaryFrom(map)
    }
    return nil
  }

  private func requireString(_ payload: [String: Any], key: String) throws -> String {
    let value = (payload[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let value, !value.isEmpty else {
      throw VaultBridgeError.invalidArgument("\(key) is required")
    }
    return value
  }

  private func requireInt(_ payload: [String: Any], key: String) throws -> Int {
    guard let value = parseInt(payload[key]) else {
      throw VaultBridgeError.invalidArgument("\(key) is required")
    }
    return value
  }

  private func requireInt64(_ payload: [String: Any], key: String) throws -> Int64 {
    guard let value = parseInt64(payload[key]) else {
      throw VaultBridgeError.invalidArgument("\(key) is required")
    }
    return value
  }

  private func requireData(_ payload: [String: Any], key: String) throws -> Data {
    if let bytes = payload[key] as? FlutterStandardTypedData {
      return bytes.data
    }
    guard let raw = payload[key] as? [Any] else {
      throw VaultBridgeError.invalidArgument("\(key) is required")
    }
    return Data(try raw.map { value in
      guard let parsed = parseInt(value), parsed >= 0, parsed <= 255 else {
        throw VaultBridgeError.invalidArgument("\(key) must be a byte array")
      }
      return UInt8(parsed)
    })
  }

  private func parseInt(_ value: Any?) -> Int? {
    switch value {
    case let int as Int:
      return int
    case let int64 as Int64:
      return Int(int64)
    case let number as NSNumber:
      return number.intValue
    case let string as String:
      return Int(string)
    default:
      return nil
    }
  }

  private func parseInt64(_ value: Any?) -> Int64? {
    switch value {
    case let int as Int:
      return Int64(int)
    case let int64 as Int64:
      return int64
    case let number as NSNumber:
      return number.int64Value
    case let string as String:
      return Int64(string)
    default:
      return nil
    }
  }

  private func dictionaryFrom(_ value: [AnyHashable: Any]) -> [String: Any] {
    var mapped: [String: Any] = [:]
    mapped.reserveCapacity(value.count)
    for (key, item) in value {
      mapped[String(describing: key)] = item
    }
    return mapped
  }

  // MARK: Storage helpers
  private func prefix(userId: String, deviceId: Int) -> String {
    "\(VaultConstants.namespace):\(userId)::\(deviceId)"
  }

  private func loadStringMap(_ prefKey: String) -> [String: String] {
    if let map = defaults.dictionary(forKey: prefKey) as? [String: String] {
      return map
    }
    return [:]
  }

  private func saveStringMap(_ prefKey: String, values: [String: String]) {
    defaults.set(values, forKey: prefKey)
  }

  private func addressKey(_ address: ProtocolAddress) -> String {
    let encodedUserId = Data(address.name.utf8)
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    return "\(encodedUserId).\(address.deviceId)"
  }

  private func addressFromKey(_ value: String) throws -> ProtocolAddress {
    guard let separator = value.lastIndex(of: ".") else {
      throw VaultBridgeError.invalidArgument("Invalid address key")
    }
    let encodedUserId = String(value[..<separator])
    let deviceIdString = String(value[value.index(after: separator)...])
    guard let deviceId = UInt32(deviceIdString) else {
      throw VaultBridgeError.invalidArgument("Invalid address key")
    }
    let padded = padBase64(encodedUserId.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/"))
    guard let userIdData = Data(base64Encoded: padded),
          let userId = String(data: userIdData, encoding: .utf8) else {
      throw VaultBridgeError.invalidArgument("Invalid address key")
    }
    return try ProtocolAddress(name: userId, deviceId: deviceId)
  }

  private func padBase64(_ value: String) -> String {
    let remainder = value.count % 4
    guard remainder != 0 else {
      return value
    }
    return value + String(repeating: "=", count: 4 - remainder)
  }

  private func toBase64(_ data: Data) -> String {
    data.base64EncodedString()
  }

  private func dataFromBase64(_ value: String) throws -> Data {
    guard let data = Data(base64Encoded: value) else {
      throw VaultBridgeError.invalidArgument("Invalid base64 payload")
    }
    return data
  }

  private func messageTypeName(_ type: CiphertextMessage.MessageType) -> String {
    if type == .preKey {
      return "prekey"
    }
    if type == .whisper {
      return "whisper"
    }
    return "unknown"
  }

  private func messageTypeCode(_ type: String) throws -> VaultMessageType {
    switch type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "prekey":
      return .preKey
    case "whisper", "ciphertext", "vault", "signal":
      return .whisper
    default:
      throw VaultBridgeError.invalidArgument("Unsupported Vault message type: \(type)")
    }
  }

  private func mapSignalError(_ error: SignalError) -> FlutterError {
    switch error {
    case .sessionNotFound(let message):
      return FlutterError(code: "vault_no_session", message: message, details: nil)
    case .invalidKeyIdentifier(let message):
      return FlutterError(code: "vault_invalid_key_id", message: message, details: nil)
    case .invalidMessage(let message) where message.lowercased().contains("reused base key"):
      return FlutterError(code: "vault_reused_base_key", message: message, details: nil)
    case .invalidArgument(let message):
      return FlutterError(code: "vault_invalid_argument", message: message, details: nil)
    case .invalidProtocolAddress(_, _, let message):
      return FlutterError(code: "vault_invalid_argument", message: message, details: nil)
    case .invalidRegistrationId(_, let message):
      return FlutterError(code: "vault_invalid_argument", message: message, details: nil)
    default:
      return FlutterError(code: "vault_bridge_error", message: String(describing: error), details: nil)
    }
  }
}

private enum VaultConstants {
  static let namespace = "the_vault_vault_bridge_v1"
  static let fingerprintIterations = 5200
  static let fingerprintVersion = 2
}

private enum VaultMessageType {
  case preKey
  case whisper
}

private enum VaultBridgeError: Error {
  case invalidArgument(String)

  var flutterError: FlutterError {
    switch self {
    case .invalidArgument(let message):
      return FlutterError(code: "vault_invalid_argument", message: message, details: nil)
    }
  }
}

private struct LocalIdentityState {
  let userId: String
  let deviceId: Int
  let registrationId: Int
  let identityKeyPair: IdentityKeyPair
}

private struct VaultAddressArg {
  let userId: String
  let deviceId: Int

  func toProtocolAddress() throws -> ProtocolAddress {
    try ProtocolAddress(name: userId, deviceId: UInt32(deviceId))
  }
}

private struct VaultDeviceIdentityArg {
  let address: VaultAddressArg
  let registrationId: Int
  let identityPublicKeyB64: String
}

private struct VaultSignedPreKeyArg {
  let keyId: Int
  let publicKeyB64: String
  let signatureB64: String
  let generatedAtMs: Int64
}

private struct VaultKyberPreKeyArg {
  let keyId: Int
  let publicKeyB64: String
  let signatureB64: String
  let generatedAtMs: Int64
}

private struct VaultOneTimePreKeyArg {
  let keyId: Int
  let publicKeyB64: String
}

private struct VaultPreKeyBundleArg {
  let address: VaultAddressArg
  let registrationId: Int
  let identityPublicKeyB64: String
  let signedPreKey: VaultSignedPreKeyArg
  let kyberPreKey: VaultKyberPreKeyArg
  let oneTimePreKey: VaultOneTimePreKeyArg?
}

private struct VaultInboundEnvelopeArg {
  let source: VaultAddressArg
  let messageType: String
  let ciphertextB64: String
}

private final class PersistedVaultStore {
  private let defaults: UserDefaults
  private let context: NullContext
  private let state: LocalIdentityState
  private let prefix: String
  private let remoteIdentitiesKey: String
  private let sessionsKey: String
  private let oneTimePreKeysKey: String
  private let signedPreKeysKey: String
  private let kyberPreKeysKey: String

  init(defaults: UserDefaults, context: NullContext, state: LocalIdentityState) {
    self.defaults = defaults
    self.context = context
    self.state = state
    self.prefix = "\(VaultConstants.namespace):\(state.userId)::\(state.deviceId)"
    self.remoteIdentitiesKey = "\(prefix):remoteIdentities"
    self.sessionsKey = "\(prefix):sessions"
    self.oneTimePreKeysKey = "\(prefix):oneTimePreKeyRecords"
    self.signedPreKeysKey = "\(prefix):signedPreKeyRecords"
    self.kyberPreKeysKey = "\(prefix):kyberPreKeyRecords"
  }

  func load() throws -> InMemorySignalProtocolStore {
    let store = InMemorySignalProtocolStore(
      identity: state.identityKeyPair,
      registrationId: UInt32(state.registrationId)
    )

    for (addressKey, identityB64) in loadStringMap(remoteIdentitiesKey) {
      let address = try addressFromKey(addressKey)
      let identity = try IdentityKey(bytes: dataFromBase64(identityB64))
      _ = try store.saveIdentity(identity, for: address, context: context)
    }

    for (addressKey, sessionB64) in loadStringMap(sessionsKey) {
      let address = try addressFromKey(addressKey)
      let session = try SessionRecord(bytes: dataFromBase64(sessionB64))
      try store.storeSession(session, for: address, context: context)
    }

    for (recordId, preKeyB64) in loadStringMap(oneTimePreKeysKey) {
      guard let id = UInt32(recordId) else { continue }
      let record = try PreKeyRecord(bytes: dataFromBase64(preKeyB64))
      try store.storePreKey(record, id: id, context: context)
    }

    for (recordId, signedPreKeyB64) in loadStringMap(signedPreKeysKey) {
      guard let id = UInt32(recordId) else { continue }
      let record = try SignedPreKeyRecord(bytes: dataFromBase64(signedPreKeyB64))
      try store.storeSignedPreKey(record, id: id, context: context)
    }

    for (recordId, kyberPreKeyB64) in loadStringMap(kyberPreKeysKey) {
      guard let id = UInt32(recordId) else { continue }
      let record = try KyberPreKeyRecord(bytes: dataFromBase64(kyberPreKeyB64))
      try store.storeKyberPreKey(record, id: id, context: context)
    }

    return store
  }

  func persist(store: InMemorySignalProtocolStore, touchedAddresses: [ProtocolAddress]) throws {
    try persistRemoteIdentities(store: store, touchedAddresses: touchedAddresses)
    try persistSessions(store: store, touchedAddresses: touchedAddresses)
    try persistOneTimePreKeys(store: store)
    try persistSignedPreKeys(store: store)
    try persistKyberPreKeys(store: store)
  }

  private func persistRemoteIdentities(
    store: InMemorySignalProtocolStore,
    touchedAddresses: [ProtocolAddress]
  ) throws {
    var identities = loadStringMap(remoteIdentitiesKey)
    for address in touchedAddresses {
      let key = addressKey(address)
      if let identity = try store.identity(for: address, context: context) {
        identities[key] = toBase64(identity.serialize())
      } else {
        identities.removeValue(forKey: key)
      }
    }
    saveStringMap(remoteIdentitiesKey, values: identities)
  }

  private func persistSessions(
    store: InMemorySignalProtocolStore,
    touchedAddresses: [ProtocolAddress]
  ) throws {
    var sessions = loadStringMap(sessionsKey)
    for address in touchedAddresses {
      let key = addressKey(address)
      if let session = try store.loadSession(for: address, context: context) {
        sessions[key] = toBase64(session.serialize())
      } else {
        sessions.removeValue(forKey: key)
      }
    }
    saveStringMap(sessionsKey, values: sessions)
  }

  private func persistOneTimePreKeys(store: InMemorySignalProtocolStore) throws {
    let current = loadStringMap(oneTimePreKeysKey)
    var updated: [String: String] = [:]
    for recordId in current.keys {
      guard let id = UInt32(recordId),
            let record = try? store.loadPreKey(id: id, context: context) else {
        continue
      }
      updated[recordId] = toBase64(record.serialize())
    }
    saveStringMap(oneTimePreKeysKey, values: updated)
  }

  private func persistSignedPreKeys(store: InMemorySignalProtocolStore) throws {
    let current = loadStringMap(signedPreKeysKey)
    var updated: [String: String] = [:]
    for recordId in current.keys {
      guard let id = UInt32(recordId),
            let record = try? store.loadSignedPreKey(id: id, context: context) else {
        continue
      }
      updated[recordId] = toBase64(record.serialize())
    }
    saveStringMap(signedPreKeysKey, values: updated)
  }

  private func persistKyberPreKeys(store: InMemorySignalProtocolStore) throws {
    let current = loadStringMap(kyberPreKeysKey)
    var updated: [String: String] = [:]
    for recordId in current.keys {
      guard let id = UInt32(recordId),
            let record = try? store.loadKyberPreKey(id: id, context: context) else {
        continue
      }
      updated[recordId] = toBase64(record.serialize())
    }
    saveStringMap(kyberPreKeysKey, values: updated)
  }

  private func loadStringMap(_ prefKey: String) -> [String: String] {
    if let map = defaults.dictionary(forKey: prefKey) as? [String: String] {
      return map
    }
    return [:]
  }

  private func saveStringMap(_ prefKey: String, values: [String: String]) {
    defaults.set(values, forKey: prefKey)
  }

  private func addressKey(_ address: ProtocolAddress) -> String {
    let encodedUserId = Data(address.name.utf8)
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    return "\(encodedUserId).\(address.deviceId)"
  }

  private func addressFromKey(_ value: String) throws -> ProtocolAddress {
    guard let separator = value.lastIndex(of: ".") else {
      throw VaultBridgeError.invalidArgument("Invalid address key")
    }
    let encodedUserId = String(value[..<separator])
    let deviceIdString = String(value[value.index(after: separator)...])
    guard let deviceId = UInt32(deviceIdString) else {
      throw VaultBridgeError.invalidArgument("Invalid address key")
    }
    let remainder = encodedUserId.count % 4
    let padded = remainder == 0
      ? encodedUserId
      : encodedUserId + String(repeating: "=", count: 4 - remainder)
    let restored = padded
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    guard let userIdData = Data(base64Encoded: restored),
          let userId = String(data: userIdData, encoding: .utf8) else {
      throw VaultBridgeError.invalidArgument("Invalid address key")
    }
    return try ProtocolAddress(name: userId, deviceId: deviceId)
  }

  private func dataFromBase64(_ value: String) throws -> Data {
    guard let data = Data(base64Encoded: value) else {
      throw VaultBridgeError.invalidArgument("Invalid base64 payload")
    }
    return data
  }

  private func toBase64(_ data: Data) -> String {
    data.base64EncodedString()
  }
}
