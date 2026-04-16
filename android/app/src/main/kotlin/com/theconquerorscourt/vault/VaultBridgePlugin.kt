package com.theconquerorscourt.vault

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
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

class VaultBridgePlugin(
  context: Context,
) : MethodChannel.MethodCallHandler {
  private val prefs: SharedPreferences = context.getSharedPreferences(
    PREFS_NAME,
    Context.MODE_PRIVATE,
  )
  private val legacyPrefs: SharedPreferences = context.getSharedPreferences(
    LEGACY_PREFS_NAME,
    Context.MODE_PRIVATE,
  )

  companion object {
    private const val channelName = "the_vault/vault"
    private const val PREFS_NAME = "the_vault_vault_bridge_v1"
    private const val LEGACY_PREFS_NAME = "the_vault_signal_bridge_v1"
    private const val TAG = "VaultBridge"

    fun registerWith(flutterEngine: FlutterEngine, context: Context) {
      MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        .setMethodCallHandler(VaultBridgePlugin(context.applicationContext))
    }
  }

  init {
    migrateLegacyPrefsIfNeeded()
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    try {
      when (call.method) {
        "getOrCreateIdentity" -> {
          val userId = requireUserId(call)
          val deviceId = requireDeviceId(call)
          val state = getOrCreateIdentity(userId = userId, deviceId = deviceId)
          result.success(identityPayload(state))
        }
        "generatePreKeyUpload" -> {
          val userId = requireUserId(call)
          val deviceId = requireDeviceId(call)
          val oneTimePreKeyCount = requireInt(call, "oneTimePreKeyCount")
          val state = getOrCreateIdentity(userId = userId, deviceId = deviceId)
          result.success(
            generatePreKeyUpload(
              state = state,
              oneTimePreKeyCount = oneTimePreKeyCount,
            ),
          )
        }
        "processPreKeyBundle" -> {
          val localAddress = requireAddress(call, "localAddress")
          val bundle = requireBundle(call)
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
          result.success(null)
        }
        "encrypt" -> {
          val localAddress = requireAddress(call, "localAddress")
          val destination = requireAddress(call, "destination")
          val plaintext = requireByteArray(call, "plaintext")
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
          result.success(
            mapOf(
              "messageType" to messageTypeName(ciphertext.type),
              "ciphertextB64" to toBase64(ciphertext.serialize()),
            ),
          )
        }
        "decrypt" -> {
          val localAddress = requireAddress(call, "localAddress")
          val envelope = requireEnvelope(call)
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
            CiphertextMessage.PREKEY_TYPE -> {
              cipher.decrypt(PreKeySignalMessage(serializedCiphertext))
            }
            CiphertextMessage.WHISPER_TYPE -> {
              cipher.decrypt(SignalMessage(serializedCiphertext))
            }
            else -> throw IllegalArgumentException(
              "Unsupported Vault message type: ${envelope.messageType}",
            )
          }
          storeHolder.persist(store, touchedAddresses = setOf(remoteProtocolAddress))
          result.success(plaintext.map { it.toInt() and 0xFF })
        }
        "archiveSession" -> {
          val localAddress = requireAddress(call, "localAddress")
          val remoteAddress = requireAddress(call, "remoteAddress")
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
          result.success(null)
        }
        "generateFingerprint" -> {
          val localAddress = requireAddress(call, "localAddress")
          val remoteIdentity = requireDeviceIdentity(call, "remoteIdentity")
          val state = getOrCreateIdentity(
            userId = localAddress.userId,
            deviceId = localAddress.deviceId,
          )
          val fingerprint = NumericFingerprintGenerator(5200).createFor(
            2,
            localAddress.userId.toByteArray(Charsets.UTF_8),
            state.identityKeyPair.publicKey,
            remoteIdentity.address.userId.toByteArray(Charsets.UTF_8),
            IdentityKey(fromBase64(remoteIdentity.identityPublicKeyB64)),
          )
          result.success(
            mapOf(
              "displayable" to fingerprint.displayableFingerprint.displayText,
              "scannableFingerprintB64" to toBase64(
                fingerprint.scannableFingerprint.serialized,
              ),
            ),
          )
        }
        else -> result.notImplemented()
      }
    } catch (error: NoSessionException) {
      Log.e(TAG, "Vault bridge method ${call.method} failed", error)
      result.error("vault_no_session", error.message, null)
    } catch (error: InvalidKeyIdException) {
      Log.e(TAG, "Vault bridge method ${call.method} failed", error)
      result.error("vault_invalid_key_id", error.message, null)
    } catch (error: ReusedBaseKeyException) {
      Log.e(TAG, "Vault bridge method ${call.method} failed", error)
      result.error("vault_reused_base_key", error.message, null)
    } catch (error: IllegalArgumentException) {
      Log.e(TAG, "Vault bridge method ${call.method} failed", error)
      result.error("vault_invalid_argument", error.message, null)
    } catch (error: Exception) {
      Log.e(TAG, "Vault bridge method ${call.method} failed", error)
      result.error("vault_bridge_error", error.message, null)
    }
  }

  private fun getOrCreateIdentity(userId: String, deviceId: Int): LocalIdentityState {
    val prefix = prefix(userId = userId, deviceId = deviceId)
    val serializedIdentity = prefs.getString("$prefix:identityKeyPair", null)
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
    prefs.edit()
      .putString("$prefix:identityKeyPair", toBase64(identityKeyPair.serialize()))
      .putInt("$prefix:registrationId", generatedRegistrationId)
      .putInt("$prefix:nextPreKeyId", 1)
      .putInt("$prefix:nextSignedPreKeyId", 1)
      .putInt("$prefix:nextKyberPreKeyId", 1)
      .apply()

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
      mapOf(
        "keyId" to preKeyId,
        "publicKeyB64" to toBase64(preKeyPair.publicKey.serialize()),
      )
    }

    return mapOf(
      "identity" to identityPayload(state),
      "signedPreKey" to mapOf(
        "keyId" to signedPreKeyId,
        "publicKeyB64" to toBase64(signedPreKeyPair.publicKey.serialize()),
        "signatureB64" to toBase64(signedPreKeySignature),
        "generatedAtMs" to generatedAtMs,
      ),
      "kyberPreKey" to mapOf(
        "keyId" to kyberPreKeyId,
        "publicKeyB64" to toBase64(kyberPreKeyPair.publicKey.serialize()),
        "signatureB64" to toBase64(kyberPreKeySignature),
        "generatedAtMs" to generatedAtMs,
      ),
      "oneTimePreKeys" to oneTimePreKeys,
    )
  }

  private fun identityPayload(state: LocalIdentityState): Map<String, Any> {
    return mapOf(
      "address" to addressPayload(userId = state.userId, deviceId = state.deviceId),
      "registrationId" to state.registrationId,
      "identityPublicKeyB64" to toBase64(state.identityKeyPair.publicKey.serialize()),
    )
  }

  private fun addressPayload(userId: String, deviceId: Int): Map<String, Any> {
    return mapOf(
      "userId" to userId,
      "deviceId" to deviceId,
    )
  }

  private fun migrateLegacyPrefsIfNeeded() {
    if (prefs.all.isNotEmpty() || legacyPrefs.all.isEmpty()) {
      return
    }
    val editor = prefs.edit()
    for ((key, value) in legacyPrefs.all) {
      when (value) {
        is String -> editor.putString(key, value)
        is Int -> editor.putInt(key, value)
        is Long -> editor.putLong(key, value)
        is Float -> editor.putFloat(key, value)
        is Boolean -> editor.putBoolean(key, value)
        is Set<*> -> {
          @Suppress("UNCHECKED_CAST")
          editor.putStringSet(key, value as Set<String>)
        }
      }
    }
    editor.apply()
  }

  private fun allocateNextId(prefix: String, counterName: String): Int {
    val key = "$prefix:$counterName"
    val nextId = prefs.getInt(key, 1)
    prefs.edit().putInt(key, nextId + 1).apply()
    return nextId
  }

  private fun allocateNextIds(prefix: String, counterName: String, count: Int): List<Int> {
    if (count <= 0) {
      return emptyList()
    }
    val key = "$prefix:$counterName"
    val nextId = prefs.getInt(key, 1)
    prefs.edit().putInt(key, nextId + count).apply()
    return (nextId until (nextId + count)).toList()
  }

  private fun storeRecord(prefKey: String, recordId: Int, serializedRecord: ByteArray) {
    val records = loadJsonStringMap(prefs, prefKey)
    records[recordId.toString()] = toBase64(serializedRecord)
    saveJsonStringMap(prefs, prefKey, records)
  }

  private fun requireUserId(call: MethodCall): String {
    val userId = call.argument<String>("userId")?.trim().orEmpty()
    require(userId.isNotEmpty()) { "userId is required" }
    return userId
  }

  private fun requireDeviceId(call: MethodCall): Int {
    return requireInt(call, "deviceId")
  }

  private fun requireInt(call: MethodCall, key: String): Int {
    return parseInt(call.argument<Any>(key))
      ?: throw IllegalArgumentException("$key is required")
  }

  private fun requireByteArray(call: MethodCall, key: String): ByteArray {
    val raw = call.argument<Any>(key)
      ?: throw IllegalArgumentException("$key is required")
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

  private fun requireAddress(call: MethodCall, key: String): VaultAddressArg {
    return parseAddress(requireMap(call, key))
  }

  private fun requireBundle(call: MethodCall): VaultPreKeyBundleArg {
    val payload = requireMap(call, "bundle")
    val oneTimePreKeyMap = optionalMap(payload, "oneTimePreKey")
    return VaultPreKeyBundleArg(
      address = parseAddress(requireMap(payload, "address")),
      registrationId = requireInt(payload, "registrationId"),
      identityPublicKeyB64 = requireString(payload, "identityPublicKeyB64"),
      signedPreKey = parseSignedPreKey(requireMap(payload, "signedPreKey")),
      kyberPreKey = parseKyberPreKey(requireMap(payload, "kyberPreKey")),
      oneTimePreKey = oneTimePreKeyMap?.let { parseOneTimePreKey(it) },
    )
  }

  private fun requireEnvelope(call: MethodCall): VaultInboundEnvelopeArg {
    val payload = requireMap(call, "envelope")
    val ciphertext = requireMap(payload, "ciphertext")
    return VaultInboundEnvelopeArg(
      source = parseAddress(requireMap(payload, "source")),
      messageType = requireString(ciphertext, "messageType"),
      ciphertextB64 = requireString(ciphertext, "ciphertextB64"),
    )
  }

  private fun requireDeviceIdentity(call: MethodCall, key: String): VaultDeviceIdentityArg {
    val payload = requireMap(call, key)
    return VaultDeviceIdentityArg(
      address = parseAddress(requireMap(payload, "address")),
      registrationId = requireInt(payload, "registrationId"),
      identityPublicKeyB64 = requireString(payload, "identityPublicKeyB64"),
    )
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

  private fun requireMap(call: MethodCall, key: String): Map<*, *> {
    return call.argument<Map<*, *>>(key)
      ?: throw IllegalArgumentException("$key is required")
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

  private fun requireLong(payload: Map<*, *>, key: String): Long {
    return parseLong(payload[key]) ?: throw IllegalArgumentException("$key is required")
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
  private val prefs: SharedPreferences,
  private val state: LocalIdentityState,
) {
  private val prefix = "${state.userId}::${state.deviceId}"
  private val remoteIdentitiesKey = "$prefix:remoteIdentities"
  private val sessionsKey = "$prefix:sessions"
  private val oneTimePreKeysKey = "$prefix:oneTimePreKeyRecords"
  private val signedPreKeysKey = "$prefix:signedPreKeyRecords"
  private val kyberPreKeysKey = "$prefix:kyberPreKeyRecords"

  private fun loadStringMap(prefKey: String): MutableMap<String, String> {
    return loadJsonStringMap(prefs, prefKey)
  }

  private fun saveStringMap(prefKey: String, values: Map<String, String>) {
    saveJsonStringMap(prefs, prefKey, values)
  }

  fun load(): InMemorySignalProtocolStore {
    val store = InMemorySignalProtocolStore(state.identityKeyPair, state.registrationId)

    loadStringMap(remoteIdentitiesKey).forEach { (addressKey, identityB64) ->
      store.saveIdentity(
        addressFromKey(addressKey),
        IdentityKey(fromBase64(identityB64)),
      )
    }
    loadStringMap(sessionsKey).forEach { (addressKey, sessionB64) ->
      store.storeSession(
        addressFromKey(addressKey),
        SessionRecord(fromBase64(sessionB64)),
      )
    }
    loadStringMap(oneTimePreKeysKey).forEach { (recordId, preKeyB64) ->
      recordId.toIntOrNull()?.let { id ->
        store.storePreKey(id, PreKeyRecord(fromBase64(preKeyB64)))
      }
    }
    loadStringMap(signedPreKeysKey).forEach { (recordId, signedPreKeyB64) ->
      recordId.toIntOrNull()?.let { id ->
        store.storeSignedPreKey(id, SignedPreKeyRecord(fromBase64(signedPreKeyB64)))
      }
    }
    loadStringMap(kyberPreKeysKey).forEach { (recordId, kyberPreKeyB64) ->
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
    val identities = loadStringMap(remoteIdentitiesKey)
    touchedAddresses.forEach { address ->
      val identity = store.getIdentity(address)
      val key = addressKey(address)
      if (identity == null) {
        identities.remove(key)
      } else {
        identities[key] = toBase64(identity.serialize())
      }
    }
    saveStringMap(remoteIdentitiesKey, identities)
  }

  private fun persistSessions(
    store: InMemorySignalProtocolStore,
    touchedAddresses: Set<SignalProtocolAddress>,
  ) {
    val sessions = loadStringMap(sessionsKey)
    touchedAddresses.forEach { address ->
      val key = addressKey(address)
      if (store.containsSession(address)) {
        sessions[key] = toBase64(store.loadSession(address).serialize())
      } else {
        sessions.remove(key)
      }
    }
    saveStringMap(sessionsKey, sessions)
  }

  private fun persistOneTimePreKeys(store: InMemorySignalProtocolStore) {
    val current = loadStringMap(oneTimePreKeysKey)
    val updated = linkedMapOf<String, String>()
    current.keys.forEach { recordId ->
      val id = recordId.toIntOrNull() ?: return@forEach
      if (store.containsPreKey(id)) {
        updated[recordId] = toBase64(store.loadPreKey(id).serialize())
      }
    }
    saveStringMap(oneTimePreKeysKey, updated)
  }

  private fun persistSignedPreKeys(store: InMemorySignalProtocolStore) {
    val updated = linkedMapOf<String, String>()
    store.loadSignedPreKeys().forEach { record ->
      updated[record.id.toString()] = toBase64(record.serialize())
    }
    saveStringMap(signedPreKeysKey, updated)
  }

  private fun persistKyberPreKeys(store: InMemorySignalProtocolStore) {
    val updated = linkedMapOf<String, String>()
    store.loadKyberPreKeys().forEach { record ->
      updated[record.id.toString()] = toBase64(record.serialize())
    }
    saveStringMap(kyberPreKeysKey, updated)
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

private fun loadJsonStringMap(
  prefs: SharedPreferences,
  prefKey: String,
): MutableMap<String, String> {
  val raw = prefs.getString(prefKey, null)
  if (raw.isNullOrBlank()) {
    return linkedMapOf()
  }
  val json = JSONObject(raw)
  val map = linkedMapOf<String, String>()
  val keys = json.keys()
  while (keys.hasNext()) {
    val key = keys.next()
    map[key] = json.optString(key, "")
  }
  return map
}

private fun saveJsonStringMap(
  prefs: SharedPreferences,
  prefKey: String,
  values: Map<String, String>,
) {
  val json = JSONObject()
  values.forEach { (key, value) -> json.put(key, value) }
  prefs.edit().putString(prefKey, json.toString()).apply()
}

private fun addressKey(address: SignalProtocolAddress): String {
  val encodedUserId = Base64.encodeToString(
    address.name.toByteArray(Charsets.UTF_8),
    Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING,
  )
  return "$encodedUserId.${address.deviceId}"
}

private fun addressFromKey(value: String): SignalProtocolAddress {
  val separator = value.lastIndexOf('.')
  require(separator > 0) { "Invalid address key" }
  val encodedUserId = value.substring(0, separator)
  val deviceId = value.substring(separator + 1).toInt()
  val userId = String(
    Base64.decode(encodedUserId, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP),
    Charsets.UTF_8,
  )
  return SignalProtocolAddress(userId, deviceId)
}

private fun toBase64(bytes: ByteArray): String {
  return Base64.encodeToString(bytes, Base64.NO_WRAP)
}

private fun fromBase64(value: String): ByteArray {
  return Base64.decode(value, Base64.DEFAULT)
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
