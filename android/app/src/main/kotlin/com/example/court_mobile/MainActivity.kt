package com.example.conquerors_court

import android.net.Uri
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// local_auth requires a FragmentActivity for biometric prompts.
class MainActivity : FlutterFragmentActivity() {
  private val toneChannelName = "com.example.conquerors_court/tones"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, toneChannelName)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "copyContentUriToFile" -> {
            val uriString = (call.argument<String>("uri") ?: "").trim()
            val outPath = (
              call.argument<String>("out_path")
                ?: call.argument<String>("outPath")
                ?: ""
              ).trim()

            if (uriString.isEmpty() || outPath.isEmpty()) {
              result.success(null)
              return@setMethodCallHandler
            }

            try {
              val copied = copyContentUriToFile(
                uriString = uriString,
                outPath = outPath,
              )
              result.success(copied)
            } catch (_: Exception) {
              result.success(null)
            }
          }
          else -> result.notImplemented()
        }
      }
  }

  private fun copyContentUriToFile(uriString: String, outPath: String): String? {
    val resolver = applicationContext.contentResolver
    val src = Uri.parse(uriString)
    val outFile = File(outPath)
    outFile.parentFile?.mkdirs()

    resolver.openInputStream(src)?.use { input ->
      outFile.outputStream().use { output ->
        input.copyTo(output)
        output.flush()
      }
    } ?: return null

    return outFile.path
  }
}
