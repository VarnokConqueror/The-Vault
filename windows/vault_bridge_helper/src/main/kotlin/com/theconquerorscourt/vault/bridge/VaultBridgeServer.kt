package com.theconquerorscourt.vault.bridge

import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.reflect.TypeToken
import org.signal.libsignal.protocol.IdentityKey
import org.signal.libsignal.protocol.IdentityKeyPair
import org.signal.libsignal.protocol.InvalidKeyIdException
import org.signal.libsignal.protocol.NoSessionException
import org.signal.libsignal.protocol.ReusedBaseKeyException
import org.signal.libsignal.protocol.SessionBuilder
import org.signal.libsignal.protocol.SessionCipher
import org.signal.libsignal.protocol.SignalProtocolAddress
import org.signal.libsignal.protocol.ecc.ECKeyPair
import org.signal.libsignal.protocol.ecc.ECPublicKey
import org.signal.libsignal.protocol.fingerprint.NumericFingerprintGenerator
import org.signal.libsignal.protocol.kem.KEMKeyPair
import org.signal.libsignal.protocol.kem.KEMKeyType
import org.signal.libsignal.protocol.kem.KEMPublicKey
import org.signal.libsignal.protocol.message.CiphertextMessage
import org.signal.libsignal.protocol.message.PreKeySignalMessage
import org.signal.libsignal.protocol.message.SignalMessage
import org.signal.libsignal.protocol.state.KyberPreKeyRecord
import org.signal.libsignal.protocol.state.PreKeyBundle
import org.signal.libsignal.protocol.state.PreKeyRecord
import org.signal.libsignal.protocol.state.SessionRecord
import org.signal.libsignal.protocol.state.SignedPreKeyRecord
import org.signal.libsignal.protocol.state.impl.InMemorySignalProtocolStore
import org.signal.libsignal.protocol.util.KeyHelper
import java.io.File
import java.io.PrintWriter
import java.nio.charset.StandardCharsets
import java.util.Base64
import java.util.Properties

fun main() {
  VaultBridgeServer().run()
}

private class VaultBridgeServer(
  private val gson: Gson = Gson(),
  private val service: VaultBridgeService = VaultBridgeService(FilePrefs.default()),
) {
  private val argsType = object : TypeToken<Map<String, Any?>>() {}.type

  fun run() {
    val writer = PrintWriter(System.out.bufferedWriter(StandardCharsets.UTF_8), true)
    System.`in`.bufferedReader(StandardCharsets.UTF_8).useLines { lines ->
      lines.forEach { line ->
        val trimmed = line.trim()
        if (trimmed.isEmpty()) {
          return@forEach
        }
        val response = handleLine(trimmed)
        writer.println(gson.toJson(response))
      }
    }
  }

  private fun handleLine(line: String): Map<String, Any?> {
    var requestId: String? = null
    return try {
      val payload = gson.fromJson(line, JsonObject::class.java)
        ?: throw BridgeRpcException("vault_invalid_argument", "request payload is required")
      requestId = payload.get("id")?.asString
      val method = payload.get("method")?.asString?.trim().orEmpty()
      if (method.isEmpty()) {
        throw BridgeRpcException("vault_invalid_argument", "method is required")
      }
      val argsElement = payload.get("args")
      val args = if (argsElement == null || argsElement.isJsonNull) {
        emptyMap<String, Any?>()
      } else {
        gson.fromJson<Map<String, Any?>>(argsElement, argsType) ?: emptyMap()
      }
      linkedMapOf(
        "id" to requestId,
        "result" to service.invoke(method, args),
      )
    } catch (error: BridgeRpcException) {
      errorResponse(
        id = requestId,
        code = error.code,
        message = error.message ?: "Bridge request failed",
      )
    } catch (error: NoSessionException) {
      errorResponse(
        id = requestId,
        code = "vault_no_session",
        message = error.message ?: "No Vault session is available",
      )
    } catch (error: InvalidKeyIdException) {
      errorResponse(
        id = requestId,
        code = "vault_invalid_key_id",
        message = error.message ?: "Invalid Vault key id",
      )
    } catch (error: ReusedBaseKeyException) {
      errorResponse(
        id = requestId,
        code = "vault_reused_base_key",
        message = error.message ?: "Reused base key",
      )
    } catch (error: IllegalArgumentException) {
      errorResponse(
        id = requestId,
        code = "vault_invalid_argument",
        message = error.message ?: "Invalid Vault bridge argument",
      )
    } catch (error: Exception) {
      error.printStackTrace(System.err)
      errorResponse(
        id = requestId,
        code = "vault_bridge_error",
        message = error.message ?: error::class.java.simpleName,
      )
    }
  }

  private fun errorResponse(
    id: String?,
    code: String,
    message: String,
  ): Map<String, Any?> {
    return linkedMapOf(
      "id" to id,
      "error" to linkedMapOf(
        "code" to code,
        "message" to message,
      ),
    )
  }
}

private class VaultBridgeService(
  private val prefs: FilePrefs,
) {
  private val fingerprintGenerator = NumericFingerprintGenerator(5200)

  fun invoke(method: String, args: Map<String, Any?>): Any? {
    return when (method) {
      "getOrCreateIdentity" -> {
        val userId = requireString(args, "userId")
        val deviceId = requireInt(args, "deviceId")
        val state = getOrCreateIdentity(userId = userId, deviceId = deviceId)
        identityPayload(state)
      }
      "generatePreKeyUpload" -> {
        val userId = requireString(args, "userId")
        val deviceId = requireInt(args, "deviceId")
        val oneTimePreKeyCount = requireInt(args, "oneTimePreKeyCount")
        val state = getOrCreateIdentity(userId = userId, deviceId = deviceId)
        generatePreKeyUpload(
          state = state,
          oneTimePreKeyCount = oneTimePreKeyCount,
        )
      }
      "processPreKeyBundle" -> {
        val localAddress = requireAddress(args, "localAddress")
        val bundle = requireBundle(args)
        val state = getOrCreateIdentity(
          userId = localAddress.userId,
          deviceId = localAddress.deviceId,
        )
        val storeHolder = PersistedVaultStore(prefs = prefs, state = state)
        val store = storeHolder.load()
        val remoteAddress = bundle.address.toProtocolAddress()
        val preKeyBundle = PreKeyBundle(
          bundle.registrationId,
          bundle.address.deviceId,
          bundle.oneTimePreKey?.keyId ?: PreKeyBundle.NULL_PRE_KEY_ID,
          bundle.oneTimePreKey?.let { ECPublicKey(fromBase64(it.publicKeyB64)) },
          bundle.signedPreKey.keyId,
          ECPublicKey(fromBase64(bundle.signedPreKey.publicKeyB64)),
          fromBase64(bundle.signedPreKey.signatureB64),
          IdentityKey(fromBase64(bundle.identityPublicKeyB64)),
          bundle.kyberPreKey.keyId,
          KEMPublicKey(fromBase64(bundle.kyberPreKey.publicKeyB64)),
          fromBase64(bundle.kyberPreKey.signatureB64),
        )
        SessionBuilder(store, remoteAddress).process(preKeyBundle)
        storeHolder.persist(store, touchedAddresses = setOf(remoteAddress))
        null
      }
      "encrypt" -> {
        val localAddress = requireAddress(args, "localAddress")
        val destination = requireAddress(args, "destination")
        val plaintext = requireByteArray(args, "plaintext")
        val state = getOrCreateIdentity(
          userId = localAddress.userId,
          deviceId = localAddress.deviceId,
        )
        val storeHolder = PersistedVaultStore(prefs = prefs, state = state)
        val store = storeHolder.load()
        val localProtocolAddress = localAddress.toProtocolAddress()
        val remoteProtocolAddress = destination.toProtocolAddress()
        val ciphertext = SessionCipher(
          store,
          localProtocolAddress,
          remoteProtocolAddress,
        ).encrypt(plaintext)
        storeHolder.persist(store, touchedAddresses = setOf(remoteProtocolAddress))
        linkedMapOf(
          "messageType" to messageTypeName(ciphertext.type),
          "ciphertextB64" to toBase64(ciphertext.serialize()),
        )
      }
      "decrypt" -> {
        val localAddress = requireAddress(args, "localAddress")
        val envelope = requireEnvelope(args)
        val state = getOrCreateIdentity(
          userId = localAddress.userId,
          deviceId = localAddress.deviceId,
        )
        val storeHolder = PersistedVaultStore(prefs = prefs, state = state)
        val store = storeHolder.load()
        val localProtocolAddress = localAddress.toProtocolAddress()
        val remoteProtocolAddress = envelope.source.toProtocolAddress()
        val cipher = SessionCipher(
          store,
          localProtocolAddress,
          remoteProtocolAddress,
        )
        val serializedCiphertext = fromBase64(envelope.ciphertextB64)
        val plaintext = when (messageTypeCode(envelope.messageType)) {
          CiphertextMessage.PREKEY_TYPE -> cipher.decrypt(PreKeySignalMessage(serializedCiphertext))
          CiphertextMessage.WHISPER_TYPE -> cipher.decrypt(SignalMessage(serializedCiphertext))
          else -> throw IllegalArgumentException(
            "Unsupported Vault message type: ${envelope.messageType}",
          )
        }
        storeHolder.persist(store, touchedAddresses = setOf(remoteProtocolAddress))
        plaintext.map { it.toInt() and 0xFF }
      }
      "archiveSession" -> {
        val localAddress = requireAddress(args, "localAddress")
        val remoteAddress = requireAddress(args, "remoteAddress")
        val state = getOrCreateIdentity(
          userId = localAddress.userId,
          deviceId = localAddress.deviceId,
        )
        val storeHolder = PersistedVaultStore(prefs = prefs, state = state)
        val store = storeHolder.load()
        val remoteProtocolAddress = remoteAddress.toProtocolAddress()
        if (store.containsSession(remoteProtocolAddress)) {
          val session = store.loadSession(remoteProtocolAddress)
          session.archiveCurrentState()
          store.storeSession(remoteProtocolAddress, session)
        }
        storeHolder.persist(store, touchedAddresses = setOf(remoteProtocolAddress))
        null
      }
      "generateFingerprint" -> {
        val localAddress = requireAddress(args, "localAddress")
        val remoteIdentity = requireDeviceIdentity(args, "remoteIdentity")
        val state = getOrCreateIdentity(
          userId = localAddress.userId,
          deviceId = localAddress.deviceId,
        )
        val fingerprint = fingerprintGenerator.createFor(
          2,
          localAddress.userId.toByteArray(Charsets.UTF_8),
          state.identityKeyPair.publicKey,
          remoteIdentity.address.userId.toByteArray(Charsets.UTF_8),
          IdentityKey(fromBase64(remoteIdentity.identityPublicKeyB64)),
        )
        linkedMapOf(
          "displayable" to fingerprint.displayableFingerprint.displayText,
          "scannableFingerprintB64" to toBase64(
            fingerprint.scannableFingerprint.serialized,
          ),
        )
      }
      else -> throw BridgeRpcException(
        code = "UNIMPLEMENTED",
        message = "Unsupported Vault bridge method: $method",
      )
    }
  }

  private fun getOrCreateIdentity(userId: String, deviceId: Int): LocalIdentityState {
    val prefix = prefix(userId = userId, deviceId = deviceId)
    val serializedIdentity = prefs.getString("$prefix:identityKeyPair")
    val registrationId = prefs.getInt("$prefix:registrationId", 0)
    if (!serializedIdentity.isNullOrBlank() && registrationId > 0) {
      return LocalIdentityState(
        userId = userId,
        deviceId = deviceId,
        registrationId = registrationId,
        identityKeyPair = IdentityKeyPair(fromBase64(serializedIdentity)),
      )
    }

    val identityKeyPair = IdentityKeyPair.generate()
    val generatedRegistrationId = KeyHelper.generateRegistrationId(false)
    prefs.putString("$prefix:identityKeyPair", toBase64(identityKeyPair.serialize()))
    prefs.putInt("$prefix:registrationId", generatedRegistrationId)
    prefs.putInt("$prefix:nextPreKeyId", 1)
    prefs.putInt("$prefix:nextSignedPreKeyId", 1)
    prefs.putInt("$prefix:nextKyberPreKeyId", 1)

    return LocalIdentityState(
      userId = userId,
      deviceId = deviceId,
      registrationId = generatedRegistrationId,
      identityKeyPair = identityKeyPair,
    )
  }

  private fun generatePreKeyUpload(
    state: LocalIdentityState,
    oneTimePreKeyCount: Int,
  ): Map<String, Any> {
    val prefix = prefix(userId = state.userId, deviceId = state.deviceId)
    val generatedAtMs = System.currentTimeMillis()

    val signedPreKeyId = allocateNextId(prefix = prefix, counterName = "nextSignedPreKeyId")
    val signedPreKeyPair = ECKeyPair.generate()
    val signedPreKeySignature = state.identityKeyPair.privateKey.calculateSignature(
      signedPreKeyPair.publicKey.serialize(),
    )
    val signedPreKeyRecord = SignedPreKeyRecord(
      signedPreKeyId,
      generatedAtMs,
      signedPreKeyPair,
      signedPreKeySignature,
    )
    storeRecord(
      prefKey = "$prefix:signedPreKeyRecords",
      recordId = signedPreKeyId,
      serializedRecord = signedPreKeyRecord.serialize(),
    )

    val kyberPreKeyId = allocateNextId(prefix = prefix, counterName = "nextKyberPreKeyId")
    val kyberPreKeyPair = KEMKeyPair.generate(KEMKeyType.KYBER_1024)
    val kyberPreKeySignature = state.identityKeyPair.privateKey.calculateSignature(
      kyberPreKeyPair.publicKey.serialize(),
    )
    val kyberPreKeyRecord = KyberPreKeyRecord(
      kyberPreKeyId,
      generatedAtMs,
      kyberPreKeyPair,
      kyberPreKeySignature,
    )
    storeRecord(
      prefKey = "$prefix:kyberPreKeyRecords",
      recordId = kyberPreKeyId,
      serializedRecord = kyberPreKeyRecord.serialize(),
    )

    val oneTimePreKeyIds = allocateNextIds(
      prefix = prefix,
      counterName = "nextPreKeyId",
      count = oneTimePreKeyCount.coerceAtLeast(0),
    )
    val oneTimePreKeys = oneTimePreKeyIds.map { preKeyId ->
      val preKeyPair = ECKeyPair.generate()
      val preKeyRecord = PreKeyRecord(preKeyId, preKeyPair)
      storeRecord(
        prefKey = "$prefix:oneTimePreKeyRecords",
        recordId = preKeyId,
        serializedRecord = preKeyRecord.serialize(),
      )
      linkedMapOf<String, Any>(
        "keyId" to preKeyId,
        "publicKeyB64" to toBase64(preKeyPair.publicKey.serialize()),
      )
    }

    return linkedMapOf(
      "identity" to identityPayload(state),
      "signedPreKey" to linkedMapOf(
        "keyId" to signedPreKeyId,
        "publicKeyB64" to toBase64(signedPreKeyPair.publicKey.serialize()),
        "signatureB64" to toBase64(signedPreKeySignature),
        "generatedAtMs" to generatedAtMs,
      ),
      "kyberPreKey" to linkedMapOf(
        "keyId" to kyberPreKeyId,
        "publicKeyB64" to toBase64(kyberPreKeyPair.publicKey.serialize()),
        "signatureB64" to toBase64(kyberPreKeySignature),
        "generatedAtMs" to generatedAtMs,
      ),
      "oneTimePreKeys" to oneTimePreKeys,
    )
  }

  private fun identityPayload(state: LocalIdentityState): Map<String, Any> {
    return linkedMapOf(
      "address" to addressPayload(userId = state.userId, deviceId = state.deviceId),
      "registrationId" to state.registrationId,
      "identityPublicKeyB64" to toBase64(state.identityKeyPair.publicKey.serialize()),
    )
  }

  private fun addressPayload(userId: String, deviceId: Int): Map<String, Any> {
    return linkedMapOf(
      "userId" to userId,
      "deviceId" to deviceId,
    )
  }

  private fun allocateNextId(prefix: String, counterName: String): Int {
    val key = "$prefix:$counterName"
    val nextId = prefs.getInt(key, 1)
    prefs.putInt(key, nextId + 1)
    return nextId
  }

  private fun allocateNextIds(prefix: String, counterName: String, count: Int): List<Int> {
    if (count <= 0) {
      return emptyList()
    }
    val key = "$prefix:$counterName"
    val nextId = prefs.getInt(key, 1)
    prefs.putInt(key, nextId + count)
    return (nextId until (nextId + count)).toList()
  }

  private fun storeRecord(prefKey: String, recordId: Int, serializedRecord: ByteArray) {
    val records = loadJsonStringMap(prefs, prefKey)
    records[recordId.toString()] = toBase64(serializedRecord)
    saveJsonStringMap(prefs, prefKey, records)
  }

  private fun requireAddress(payload: Map<*, *>, key: String): VaultAddressArg {
    return parseAddress(requireMap(payload, key))
  }

  private fun requireBundle(payload: Map<*, *>): VaultPreKeyBundleArg {
    val bundle = requireMap(payload, "bundle")
    val oneTimePreKeyMap = optionalMap(bundle, "oneTimePreKey")
    return VaultPreKeyBundleArg(
      address = parseAddress(requireMap(bundle, "address")),
      registrationId = requireInt(bundle, "registrationId"),
      identityPublicKeyB64 = requireString(bundle, "identityPublicKeyB64"),
      signedPreKey = parseSignedPreKey(requireMap(bundle, "signedPreKey")),
      kyberPreKey = parseKyberPreKey(requireMap(bundle, "kyberPreKey")),
      oneTimePreKey = oneTimePreKeyMap?.let { parseOneTimePreKey(it) },
    )
  }

  private fun requireEnvelope(payload: Map<*, *>): VaultInboundEnvelopeArg {
    val envelope = requireMap(payload, "envelope")
    val ciphertext = requireMap(envelope, "ciphertext")
    return VaultInboundEnvelopeArg(
      source = parseAddress(requireMap(envelope, "source")),
      messageType = requireString(ciphertext, "messageType"),
      ciphertextB64 = requireString(ciphertext, "ciphertextB64"),
    )
  }

  private fun requireDeviceIdentity(payload: Map<*, *>, key: String): VaultDeviceIdentityArg {
    val value = requireMap(payload, key)
    return VaultDeviceIdentityArg(
      address = parseAddress(requireMap(value, "address")),
      registrationId = requireInt(value, "registrationId"),
      identityPublicKeyB64 = requireString(value, "identityPublicKeyB64"),
    )
  }

  private fun requireMap(payload: Map<*, *>, key: String): Map<*, *> {
    return payload[key] as? Map<*, *>
      ?: throw IllegalArgumentException("$key is required")
  }

  private fun optionalMap(payload: Map<*, *>, key: String): Map<*, *>? {
    return payload[key] as? Map<*, *>
  }

  private fun requireString(payload: Map<*, *>, key: String): String {
    return payload[key]?.toString()?.trim()?.takeIf { it.isNotEmpty() }
      ?: throw IllegalArgumentException("$key is required")
  }

  private fun requireInt(payload: Map<*, *>, key: String): Int {
    return parseInt(payload[key]) ?: throw IllegalArgumentException("$key is required")
  }

  private fun parseAddress(payload: Map<*, *>): VaultAddressArg {
    return VaultAddressArg(
      userId = requireString(payload, "userId"),
      deviceId = requireInt(payload, "deviceId"),
    )
  }

  private fun parseSignedPreKey(payload: Map<*, *>): VaultSignedPreKeyArg {
    return VaultSignedPreKeyArg(
      keyId = requireInt(payload, "keyId"),
      publicKeyB64 = requireString(payload, "publicKeyB64"),
      signatureB64 = requireString(payload, "signatureB64"),
      generatedAtMs = requireLong(payload, "generatedAtMs"),
    )
  }

  private fun parseKyberPreKey(payload: Map<*, *>): VaultKyberPreKeyArg {
    return VaultKyberPreKeyArg(
      keyId = requireInt(payload, "keyId"),
      publicKeyB64 = requireString(payload, "publicKeyB64"),
      signatureB64 = requireString(payload, "signatureB64"),
      generatedAtMs = requireLong(payload, "generatedAtMs"),
    )
  }

  private fun parseOneTimePreKey(payload: Map<*, *>): VaultOneTimePreKeyArg {
    return VaultOneTimePreKeyArg(
      keyId = requireInt(payload, "keyId"),
      publicKeyB64 = requireString(payload, "publicKeyB64"),
    )
  }

  private fun requireLong(payload: Map<*, *>, key: String): Long {
    return parseLong(payload[key]) ?: throw IllegalArgumentException("$key is required")
  }

  private fun requireByteArray(payload: Map<*, *>, key: String): ByteArray {
    val raw = payload[key] ?: throw IllegalArgumentException("$key is required")
    return when (raw) {
      is ByteArray -> raw
      is List<*> -> raw
        .map { parseInt(it) ?: throw IllegalArgumentException("$key must be a byte array") }
        .map { it and 0xFF }
        .map { it.toByte() }
        .toByteArray()
      else -> throw IllegalArgumentException("$key must be a byte array")
    }
  }

  private fun parseInt(value: Any?): Int? {
    return when (value) {
      is Int -> value
      is Long -> value.toInt()
      is Number -> value.toInt()
      is String -> value.toIntOrNull()
      else -> null
    }
  }

  private fun parseLong(value: Any?): Long? {
    return when (value) {
      is Int -> value.toLong()
      is Long -> value
      is Number -> value.toLong()
      is String -> value.toLongOrNull()
      else -> null
    }
  }

  private fun prefix(userId: String, deviceId: Int): String {
    return "$userId::$deviceId"
  }
}

private class PersistedVaultStore(
  private val prefs: FilePrefs,
  private val state: LocalIdentityState,
) {
  private val prefix = "${state.userId}::${state.deviceId}"
  private val remoteIdentitiesKey = "$prefix:remoteIdentities"
  private val sessionsKey = "$prefix:sessions"
  private val oneTimePreKeysKey = "$prefix:oneTimePreKeyRecords"
  private val signedPreKeysKey = "$prefix:signedPreKeyRecords"
  private val kyberPreKeysKey = "$prefix:kyberPreKeyRecords"

  fun load(): InMemorySignalProtocolStore {
    val store = InMemorySignalProtocolStore(state.identityKeyPair, state.registrationId)

    loadJsonStringMap(prefs, remoteIdentitiesKey).forEach { (addressKey, identityB64) ->
      store.saveIdentity(
        addressFromKey(addressKey),
        IdentityKey(fromBase64(identityB64)),
      )
    }
    loadJsonStringMap(prefs, sessionsKey).forEach { (addressKey, sessionB64) ->
      store.storeSession(
        addressFromKey(addressKey),
        SessionRecord(fromBase64(sessionB64)),
      )
    }
    loadJsonStringMap(prefs, oneTimePreKeysKey).forEach { (recordId, preKeyB64) ->
      recordId.toIntOrNull()?.let { id ->
        store.storePreKey(id, PreKeyRecord(fromBase64(preKeyB64)))
      }
    }
    loadJsonStringMap(prefs, signedPreKeysKey).forEach { (recordId, signedPreKeyB64) ->
      recordId.toIntOrNull()?.let { id ->
        store.storeSignedPreKey(id, SignedPreKeyRecord(fromBase64(signedPreKeyB64)))
      }
    }
    loadJsonStringMap(prefs, kyberPreKeysKey).forEach { (recordId, kyberPreKeyB64) ->
      recordId.toIntOrNull()?.let { id ->
        store.storeKyberPreKey(id, KyberPreKeyRecord(fromBase64(kyberPreKeyB64)))
      }
    }

    return store
  }

  fun persist(
    store: InMemorySignalProtocolStore,
    touchedAddresses: Set<SignalProtocolAddress>,
  ) {
    persistRemoteIdentities(store, touchedAddresses)
    persistSessions(store, touchedAddresses)
    persistOneTimePreKeys(store)
    persistSignedPreKeys(store)
    persistKyberPreKeys(store)
  }

  private fun persistRemoteIdentities(
    store: InMemorySignalProtocolStore,
    touchedAddresses: Set<SignalProtocolAddress>,
  ) {
    val identities = loadJsonStringMap(prefs, remoteIdentitiesKey)
    touchedAddresses.forEach { address ->
      val identity = store.getIdentity(address)
      val key = addressKey(address)
      if (identity == null) {
        identities.remove(key)
      } else {
        identities[key] = toBase64(identity.serialize())
      }
    }
    saveJsonStringMap(prefs, remoteIdentitiesKey, identities)
  }

  private fun persistSessions(
    store: InMemorySignalProtocolStore,
    touchedAddresses: Set<SignalProtocolAddress>,
  ) {
    val sessions = loadJsonStringMap(prefs, sessionsKey)
    touchedAddresses.forEach { address ->
      val key = addressKey(address)
      if (store.containsSession(address)) {
        sessions[key] = toBase64(store.loadSession(address).serialize())
      } else {
        sessions.remove(key)
      }
    }
    saveJsonStringMap(prefs, sessionsKey, sessions)
  }

  private fun persistOneTimePreKeys(store: InMemorySignalProtocolStore) {
    val current = loadJsonStringMap(prefs, oneTimePreKeysKey)
    val updated = linkedMapOf<String, String>()
    current.keys.forEach { recordId ->
      val id = recordId.toIntOrNull() ?: return@forEach
      if (store.containsPreKey(id)) {
        updated[recordId] = toBase64(store.loadPreKey(id).serialize())
      }
    }
    saveJsonStringMap(prefs, oneTimePreKeysKey, updated)
  }

  private fun persistSignedPreKeys(store: InMemorySignalProtocolStore) {
    val updated = linkedMapOf<String, String>()
    store.loadSignedPreKeys().forEach { record ->
      updated[record.id.toString()] = toBase64(record.serialize())
    }
    saveJsonStringMap(prefs, signedPreKeysKey, updated)
  }

  private fun persistKyberPreKeys(store: InMemorySignalProtocolStore) {
    val updated = linkedMapOf<String, String>()
    store.loadKyberPreKeys().forEach { record ->
      updated[record.id.toString()] = toBase64(record.serialize())
    }
    saveJsonStringMap(prefs, kyberPreKeysKey, updated)
  }
}

private class FilePrefs(
  private val file: File,
) {
  private val properties = Properties()

  init {
    if (file.exists()) {
      file.inputStream().use(properties::load)
    }
  }

  @Synchronized
  fun getString(key: String): String? = properties.getProperty(key)

  @Synchronized
  fun getInt(key: String, defaultValue: Int): Int {
    return properties.getProperty(key)?.toIntOrNull() ?: defaultValue
  }

  @Synchronized
  fun putString(key: String, value: String) {
    properties.setProperty(key, value)
    flush()
  }

  @Synchronized
  fun putInt(key: String, value: Int) {
    properties.setProperty(key, value.toString())
    flush()
  }

  @Synchronized
  fun putJsonString(key: String, value: String) {
    properties.setProperty(key, value)
    flush()
  }

  companion object {
    fun default(): FilePrefs {
      val baseDir = sequenceOf(
        System.getenv("VAULT_BRIDGE_STORE_DIR"),
        System.getenv("LOCALAPPDATA"),
        System.getenv("APPDATA"),
        System.getProperty("user.home"),
      ).firstOrNull { !it.isNullOrBlank() }
        ?: throw IllegalStateException("Could not resolve a writable prefs directory")
      val file = File(baseDir, "The Vault\\vault_bridge_v1.properties")
      file.parentFile?.mkdirs()
      return FilePrefs(file)
    }
  }

  private fun flush() {
    file.parentFile?.mkdirs()
    file.outputStream().use { stream ->
      properties.store(stream, "The Vault Windows bridge state")
    }
  }
}

private data class LocalIdentityState(
  val userId: String,
  val deviceId: Int,
  val registrationId: Int,
  val identityKeyPair: IdentityKeyPair,
)

private data class VaultAddressArg(
  val userId: String,
  val deviceId: Int,
) {
  fun toProtocolAddress(): SignalProtocolAddress {
    return SignalProtocolAddress(userId, deviceId)
  }
}

private data class VaultSignedPreKeyArg(
  val keyId: Int,
  val publicKeyB64: String,
  val signatureB64: String,
  val generatedAtMs: Long,
)

private data class VaultDeviceIdentityArg(
  val address: VaultAddressArg,
  val registrationId: Int,
  val identityPublicKeyB64: String,
)

private data class VaultKyberPreKeyArg(
  val keyId: Int,
  val publicKeyB64: String,
  val signatureB64: String,
  val generatedAtMs: Long,
)

private data class VaultOneTimePreKeyArg(
  val keyId: Int,
  val publicKeyB64: String,
)

private data class VaultPreKeyBundleArg(
  val address: VaultAddressArg,
  val registrationId: Int,
  val identityPublicKeyB64: String,
  val signedPreKey: VaultSignedPreKeyArg,
  val kyberPreKey: VaultKyberPreKeyArg,
  val oneTimePreKey: VaultOneTimePreKeyArg?,
)

private data class VaultInboundEnvelopeArg(
  val source: VaultAddressArg,
  val messageType: String,
  val ciphertextB64: String,
)

private class BridgeRpcException(
  val code: String,
  override val message: String,
) : RuntimeException(message)

private val jsonGson = Gson()
private val stringMapType = object : TypeToken<MutableMap<String, String>>() {}.type

private fun loadJsonStringMap(
  prefs: FilePrefs,
  prefKey: String,
): MutableMap<String, String> {
  val raw = prefs.getString(prefKey)
  if (raw.isNullOrBlank()) {
    return linkedMapOf()
  }
  return jsonGson.fromJson<MutableMap<String, String>>(raw, stringMapType) ?: linkedMapOf()
}

private fun saveJsonStringMap(
  prefs: FilePrefs,
  prefKey: String,
  values: Map<String, String>,
) {
  prefs.putJsonString(prefKey, jsonGson.toJson(values))
}

private fun addressKey(address: SignalProtocolAddress): String {
  val encodedUserId = Base64.getUrlEncoder()
    .withoutPadding()
    .encodeToString(address.name.toByteArray(Charsets.UTF_8))
  return "$encodedUserId.${address.deviceId}"
}

private fun addressFromKey(value: String): SignalProtocolAddress {
  val separator = value.lastIndexOf('.')
  require(separator > 0) { "Invalid address key" }
  val encodedUserId = value.substring(0, separator)
  val deviceId = value.substring(separator + 1).toInt()
  val userId = String(
    Base64.getUrlDecoder().decode(encodedUserId),
    Charsets.UTF_8,
  )
  return SignalProtocolAddress(userId, deviceId)
}

private fun toBase64(bytes: ByteArray): String {
  return Base64.getEncoder().encodeToString(bytes)
}

private fun fromBase64(value: String): ByteArray {
  return Base64.getDecoder().decode(value)
}

private fun messageTypeName(type: Int): String {
  return when (type) {
    CiphertextMessage.PREKEY_TYPE -> "prekey"
    CiphertextMessage.WHISPER_TYPE -> "whisper"
    else -> "unknown"
  }
}

private fun messageTypeCode(type: String): Int {
  return when (type.trim().lowercase()) {
    "prekey" -> CiphertextMessage.PREKEY_TYPE
    "whisper", "ciphertext", "vault", "signal" -> CiphertextMessage.WHISPER_TYPE
    else -> -1
  }
}
