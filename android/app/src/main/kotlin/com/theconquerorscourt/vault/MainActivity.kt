package com.theconquerorscourt.vault

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

// local_auth requires a FragmentActivity for biometric prompts.
class MainActivity : FlutterFragmentActivity() {
  private val updateLogTag = "VaultUpdater"
  private val toneChannelName = "com.theconquerorscourt.vault/tones"
  private val updatesChannelName = "com.theconquerorscourt.vault/updates"
  private var pendingInstallResult: MethodChannel.Result? = null
  private val installLauncher: ActivityResultLauncher<Intent> =
    registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { activityResult ->
      val result = pendingInstallResult ?: return@registerForActivityResult
      pendingInstallResult = null

      val installStatus = activityResult.data?.getIntExtra(
        PackageInstaller.EXTRA_STATUS,
        Int.MIN_VALUE,
      ) ?: Int.MIN_VALUE

      val payload = when {
        activityResult.resultCode == Activity.RESULT_OK ||
            installStatus == PackageInstaller.STATUS_SUCCESS -> {
          logUpdateCategory("installer_completed")
          installResult(
            status = "installer_completed",
            message = "Android finished installing the Vault update.",
          )
        }
        installStatus == PackageInstaller.STATUS_FAILURE_ABORTED ||
            activityResult.resultCode == Activity.RESULT_CANCELED -> {
          logUpdateCategory("installer_canceled")
          installResult(
            status = "installer_canceled",
            message = "Update canceled. Your current Vault install and local-only data were left unchanged.",
          )
        }
        installStatus == PackageInstaller.STATUS_FAILURE_BLOCKED -> {
          logUpdateCategory("installer_blocked")
          installResult(
            status = "installer_blocked",
            message = "Android blocked the update before installation finished.",
          )
        }
        installStatus == PackageInstaller.STATUS_FAILURE_STORAGE -> {
          logUpdateCategory("installer_storage")
          installResult(
            status = "installer_storage",
            message = "Android needs more free space before the update can finish.",
          )
        }
        installStatus == PackageInstaller.STATUS_FAILURE_CONFLICT -> {
          logUpdateCategory("signature_mismatch")
          installResult(
            status = "signature_mismatch",
            message = signerMismatchMessage(),
          )
        }
        installStatus == PackageInstaller.STATUS_FAILURE_INVALID -> {
          logUpdateCategory("invalid_apk")
          installResult(
            status = "invalid_apk",
            message = "Android reported that the downloaded APK is invalid.",
          )
        }
        installStatus == PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> {
          logUpdateCategory("installer_incompatible")
          installResult(
            status = "installer_incompatible",
            message = "Android reported that this Vault APK is not compatible with this device.",
          )
        }
        installStatus == PackageInstaller.STATUS_FAILURE_TIMEOUT -> {
          logUpdateCategory("installer_timeout")
          installResult(
            status = "installer_timeout",
            message = "Android did not finish the update in time. Please try again.",
          )
        }
        else -> {
          logUpdateCategory("installer_failed")
          installResult(
            status = "installer_failed",
            message = "Android could not finish installing the Vault update.",
          )
        }
      }

      result.success(payload)
    }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    VaultBridgePlugin.registerWith(flutterEngine, applicationContext)

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

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updatesChannelName)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "installDownloadedApk" -> {
            val apkPath = (
              call.argument<String>("path")
                ?: call.argument<String>("apkPath")
                ?: ""
              ).trim()
            installDownloadedApk(apkPath, result)
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

  private fun installDownloadedApk(apkPath: String, result: MethodChannel.Result) {
    if (pendingInstallResult != null) {
      logUpdateCategory("update_busy")
      result.success(
        installResult(
          status = "update_busy",
          message = "Another Vault update install is already in progress.",
        ),
      )
      return
    }

    if (apkPath.isEmpty()) {
      logUpdateCategory("file_missing")
      result.success(
        installResult(
          status = "file_missing",
          message = "The downloaded APK path was missing.",
        ),
      )
      return
    }

    val apkFile = File(apkPath)
    if (!apkFile.exists()) {
      logUpdateCategory("file_missing")
      result.success(
        installResult(
          status = "file_missing",
          message = "The downloaded APK could not be found.",
        ),
      )
      return
    }

    val archiveInfo = getArchivePackageInfo(apkFile.path)
      ?: run {
        logUpdateCategory("invalid_apk")
        result.success(
          installResult(
            status = "invalid_apk",
            message = "The downloaded APK could not be parsed by Android.",
          ),
        )
        return
      }
    archiveInfo.applicationInfo?.sourceDir = apkFile.path
    archiveInfo.applicationInfo?.publicSourceDir = apkFile.path

    val installedPackageName = applicationContext.packageName
    val archivePackageName = archiveInfo.packageName.orEmpty().trim()
    if (archivePackageName.isEmpty() || archivePackageName != installedPackageName) {
      logUpdateCategory("package_mismatch")
      result.success(
        installResult(
          status = "package_mismatch",
          message = "The downloaded package does not match this Vault install.",
        ),
      )
      return
    }

    val installedInfo = getInstalledPackageInfo(installedPackageName)
    val archiveVersionCode = versionCodeOf(archiveInfo)
    val installedVersionCode = installedInfo?.let(::versionCodeOf)
    if (
      installedVersionCode != null &&
      archiveVersionCode > 0 &&
      archiveVersionCode <= installedVersionCode
    ) {
      logUpdateCategory("not_newer")
      result.success(
        installResult(
          status = "not_newer",
          message = "The downloaded APK is not newer than the Vault build already installed.",
        ),
      )
      return
    }

    val archiveSigners = signerDigestsFor(archiveInfo)
    val installedSigners = installedInfo?.let(::signerDigestsFor).orEmpty()
    if (
      archiveSigners.isNotEmpty() &&
      installedSigners.isNotEmpty() &&
      archiveSigners != installedSigners
    ) {
      logUpdateCategory("signature_mismatch")
      result.success(
        installResult(
          status = "signature_mismatch",
          message = signerMismatchMessage(),
        ),
      )
      return
    }

    if (
      Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
      !packageManager.canRequestPackageInstalls()
    ) {
      openUnknownAppSourcesSettings()
      logUpdateCategory("permission_required")
      result.success(
        installResult(
          status = "permission_required",
          message = "Allow installs from The Vault in Android settings, then tap the update button again.",
        ),
      )
      return
    }

    try {
      val authority = "${applicationContext.packageName}.fileprovider"
      val contentUri = FileProvider.getUriForFile(this, authority, apkFile)
      val installIntent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
        data = contentUri
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
        putExtra(Intent.EXTRA_RETURN_RESULT, true)
      }
      pendingInstallResult = result
      logUpdateCategory("installer_started")
      installLauncher.launch(installIntent)
    } catch (_: ActivityNotFoundException) {
      pendingInstallResult = null
      logUpdateCategory("installer_unavailable")
      result.success(
        installResult(
          status = "installer_unavailable",
          message = "Android could not open the package installer on this device.",
        ),
      )
    } catch (error: Exception) {
      pendingInstallResult = null
      logUpdateCategory("installer_error")
      result.success(
        installResult(
          status = "error",
          message = "Android could not start the package installer.",
        ),
      )
    }
  }

  private fun getArchivePackageInfo(apkPath: String): PackageInfo? {
    val flags = packageInfoFlags()
    return packageManager.getPackageArchiveInfo(apkPath, flags)
  }

  private fun getInstalledPackageInfo(packageName: String): PackageInfo? {
    val flags = packageInfoFlags()
    return try {
      packageManager.getPackageInfo(packageName, flags)
    } catch (_: PackageManager.NameNotFoundException) {
      null
    }
  }

  private fun packageInfoFlags(): Int {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      PackageManager.GET_SIGNING_CERTIFICATES
    } else {
      @Suppress("DEPRECATION")
      PackageManager.GET_SIGNATURES
    }
  }

  private fun versionCodeOf(packageInfo: PackageInfo): Long {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      packageInfo.longVersionCode
    } else {
      @Suppress("DEPRECATION")
      packageInfo.versionCode.toLong()
    }
  }

  private fun signerDigestsFor(packageInfo: PackageInfo): Set<String> {
    val signerBytes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
      packageInfo.signingInfo?.apkContentsSigners?.map { it.toByteArray() }
    } else {
      @Suppress("DEPRECATION")
      packageInfo.signatures?.map { it.toByteArray() }
    } ?: emptyList()

    return signerBytes.map(::sha256Hex).toSet()
  }

  private fun sha256Hex(bytes: ByteArray): String {
    val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
    return digest.joinToString(separator = "") { byte -> "%02x".format(byte) }
  }

  private fun openUnknownAppSourcesSettings() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      return
    }
    val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
      data = Uri.parse("package:${applicationContext.packageName}")
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    startActivity(intent)
  }

  private fun signerMismatchMessage(): String {
    return "Android blocked this in-place Vault update because the app already installed on this phone was signed with a different certificate. This is an Android security protection. If you have local-only chats or settings, back them up first in Data & Storage > Backup & Restore. Then uninstall the current Vault once, install the current release fresh from the download site, and future updates should work from this signing line."
  }

  private fun logUpdateCategory(category: String) {
    Log.i(updateLogTag, "category=$category")
  }

  private fun installResult(
    status: String,
    message: String,
  ): Map<String, Any?> {
    return mapOf(
      "status" to status,
      "message" to message,
    )
  }
}
