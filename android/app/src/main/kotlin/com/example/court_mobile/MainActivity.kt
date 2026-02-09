package com.example.conquerors_court

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// local_auth requires a FragmentActivity for biometric prompts.
class MainActivity : FlutterFragmentActivity() {
  private val toneChannelName = "com.example.conquerors_court/tones"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, toneChannelName)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "importNotificationTone" -> {
            val key = (call.argument<String>("key") ?: "").trim()
            val displayName = (
              call.argument<String>("display_name")
                ?: call.argument<String>("displayName")
                ?: "tone"
              ).trim().ifEmpty { "tone" }
            val bytes = call.argument<ByteArray>("bytes")
            val mime = (call.argument<String>("mime") ?: "audio/*").trim().ifEmpty {
              "audio/*"
            }

            if (bytes == null || bytes.isEmpty()) {
              result.success(null)
              return@setMethodCallHandler
            }

            try {
              val uri = importToneToMediaStore(
                key = key,
                displayName = displayName,
                bytes = bytes,
                mime = mime,
              )
              result.success(uri)
            } catch (_: Exception) {
              result.success(null)
            }
          }
          else -> result.notImplemented()
        }
      }
  }

  private fun importToneToMediaStore(
    key: String,
    displayName: String,
    bytes: ByteArray,
    mime: String,
  ): String? {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
      // On older devices we'd need legacy storage permissions and/or SAF.
      // Fall back to app-private file URIs there.
      return null
    }

    val safeKey = key.replace(Regex("[^a-zA-Z0-9_-]"), "_").ifEmpty { "tone" }
    val ext = displayName.substringAfterLast('.', "").trim().lowercase()
    val fileName = if (ext.isNotEmpty() && ext.length <= 5) "$safeKey.$ext" else safeKey

    val relativePath = Environment.DIRECTORY_NOTIFICATIONS + "/TheVault"
    val values = ContentValues().apply {
      put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
      put(MediaStore.MediaColumns.MIME_TYPE, mime)
      put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
      put(MediaStore.Audio.Media.IS_NOTIFICATION, 1)
      put(MediaStore.Audio.Media.IS_RINGTONE, 0)
      put(MediaStore.Audio.Media.IS_ALARM, 0)
      put(MediaStore.Audio.Media.IS_MUSIC, 0)
      put(MediaStore.MediaColumns.IS_PENDING, 1)
    }

    val resolver = applicationContext.contentResolver
    val collection = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
    val itemUri = resolver.insert(collection, values) ?: return null

    resolver.openOutputStream(itemUri)?.use { out ->
      out.write(bytes)
      out.flush()
    } ?: return null

    val doneValues = ContentValues().apply {
      put(MediaStore.MediaColumns.IS_PENDING, 0)
    }
    resolver.update(itemUri, doneValues, null, null)

    return itemUri.toString()
  }
}
