param(
  [string]$OutputDir = "C:\Users\Varnok\The-Vault\build\vault-download-site",
  [string]$ApkPath = "C:\Users\Varnok\The-Vault\build\app\outputs\flutter-apk\app-release.apk",
  [string]$WindowsInstallerPath = "",
  [string]$DonateUrl = "https://www.paypal.com/biz/profile/varnoksystemsllc"
)

$ErrorActionPreference = "Stop"

$repoRoot = "C:\Users\Varnok\The-Vault"
$siteBaseUrl = "https://vault.theconquerorscourt.com"
$templatePath = Join-Path $repoRoot "site\vault-download\index.template.html"
$privacyPath = Join-Path $repoRoot "web\privacy-policy.html"
$termsPath = Join-Path $repoRoot "web\terms-of-service.html"
$crownPngPath = Join-Path $repoRoot "assets\images\The Vault Crown.png"
$crownSvgPath = Join-Path $repoRoot "assets\images\The Vault Crown.svg"
$brandPath = Join-Path $repoRoot "assets\brand\vault_shield.svg"
if (Test-Path $crownPngPath) {
  $brandPath = $crownPngPath
} elseif (Test-Path $crownSvgPath) {
  $brandPath = $crownSvgPath
}
if (-not (Test-Path $brandPath)) {
  $brandPath = Join-Path $repoRoot "assets\brand\vault_crown.svg"
}
$faviconPath = Join-Path $repoRoot "web\favicon.png"
$pubspecPath = Join-Path $repoRoot "pubspec.yaml"
$distDir = Join-Path $repoRoot "build\dist"
$assetLinksPackageName = "com.theconquerorscourt.vault"
$assetLinksSha256 = "79:57:B5:AE:48:EE:45:CB:D8:80:D1:BE:7B:36:67:F1:D7:AA:7D:C9:7D:A8:C6:27:E6:38:CE:B7:2F:58:3B:7B"

if (-not (Test-Path $ApkPath)) {
  throw "APK not found at $ApkPath. Build the release APK before packaging the download site."
}

$versionLine = (Get-Content -LiteralPath $pubspecPath | Select-String '^version:\s*(.+)$' | Select-Object -First 1).Matches[0].Groups[1].Value.Trim()
$versionDisplay = $versionLine

if ([string]::IsNullOrWhiteSpace($WindowsInstallerPath)) {
  $parts = $versionDisplay -split '\+'
  $appVersion = $parts[0]
  $expectedPath = Join-Path $distDir "the-vault-windows-setup-v$appVersion.exe"
  
  # Try to find the current release version, or fall back to the latest available
  if (Test-Path $expectedPath) {
    $WindowsInstallerPath = $expectedPath
  } else {
    # Look for any windows setup exe in dist, prefer latest
    $availableInstallers = @(Get-ChildItem -Path $distDir -Filter "the-vault-windows-setup-*.exe" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($availableInstallers.Count -gt 0) {
      $WindowsInstallerPath = $availableInstallers[0].FullName
      Write-Host "[WARN] Using latest available Windows installer: $(Split-Path $WindowsInstallerPath -Leaf)" -ForegroundColor Yellow
      Write-Host "  (Expected: $(Split-Path $expectedPath -Leaf))" -ForegroundColor Yellow
    }
  }
}

if (-not (Test-Path $WindowsInstallerPath)) {
  throw "Windows installer not found. Expected: $expectedPath`nRun: flutter build windows -v`nThen: .\tool\build_windows_installer.ps1"
}

if (Test-Path $OutputDir) {
  Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$downloadsDir = Join-Path $OutputDir "downloads"
$wellKnownDir = Join-Path $OutputDir ".well-known"
New-Item -ItemType Directory -Path $OutputDir | Out-Null
New-Item -ItemType Directory -Path $downloadsDir | Out-Null
New-Item -ItemType Directory -Path $wellKnownDir | Out-Null

# Extract just the semantic version (e.g., "1.0.7" from "1.0.7+1")
$parts = $versionDisplay -split '\+'
$cleanVersion = $parts[0]

$apkFileName = "the-vault-android-v${cleanVersion}.apk"
$outputApkPath = Join-Path $downloadsDir $apkFileName
Copy-Item -LiteralPath $ApkPath -Destination $outputApkPath

$windowsInstallerFileName = "the-vault-windows-setup-v${cleanVersion}.exe"
$outputWindowsInstallerPath = Join-Path $downloadsDir $windowsInstallerFileName
Copy-Item -LiteralPath $WindowsInstallerPath -Destination $outputWindowsInstallerPath

$apkItem = Get-Item -LiteralPath $outputApkPath
$apkSizeMb = [math]::Round($apkItem.Length / 1MB, 1).ToString("0.0")
$apkHash = (Get-FileHash -LiteralPath $outputApkPath -Algorithm SHA256).Hash.ToUpperInvariant()
$windowsInstallerItem = Get-Item -LiteralPath $outputWindowsInstallerPath
$windowsInstallerSizeMb = [math]::Round($windowsInstallerItem.Length / 1MB, 1).ToString("0.0")
$windowsInstallerHash = (Get-FileHash -LiteralPath $outputWindowsInstallerPath -Algorithm SHA256).Hash.ToUpperInvariant()
$updatedAt = @($apkItem.LastWriteTime, $windowsInstallerItem.LastWriteTime) | Sort-Object -Descending | Select-Object -First 1
$updatedAtDisplay = $updatedAt.ToString("MMMM d, yyyy")

$html = Get-Content -LiteralPath $templatePath -Raw
$html = $html.Replace("__APK_FILE__", $apkFileName)
$html = $html.Replace("__APK_VERSION__", $versionDisplay)
$html = $html.Replace("__APK_SIZE_MB__", $apkSizeMb)
$html = $html.Replace("__APK_SHA256__", $apkHash)
$html = $html.Replace("__WIN_INSTALLER_FILE__", $windowsInstallerFileName)
$html = $html.Replace("__WIN_INSTALLER_SIZE_MB__", $windowsInstallerSizeMb)
$html = $html.Replace("__WIN_INSTALLER_SHA256__", $windowsInstallerHash)
$html = $html.Replace("__UPDATED_AT__", $updatedAtDisplay)
$html = $html.Replace("__DONATE_URL__", $DonateUrl)
$brandExtension = [System.IO.Path]::GetExtension($brandPath)
$brandOutputName = "vault-brand$brandExtension"
$html = $html.Replace("__BRAND_FILE__", $brandOutputName)

Set-Content -LiteralPath (Join-Path $OutputDir "index.html") -Value $html -Encoding UTF8
Set-Content -LiteralPath (Join-Path $downloadsDir "$apkFileName.sha256.txt") -Value "$apkHash  $apkFileName" -Encoding ASCII
Set-Content -LiteralPath (Join-Path $downloadsDir "$windowsInstallerFileName.sha256.txt") -Value "$windowsInstallerHash  $windowsInstallerFileName" -Encoding ASCII
$latestManifest = @{
  version = $versionDisplay
  publishedAt = $updatedAt.ToString("o")
  websiteUrl = "$siteBaseUrl/"
  android = @{
    url = "$siteBaseUrl/downloads/$apkFileName"
    sha256 = $apkHash
    sizeMb = $apkSizeMb
  }
  windows = @{
    url = "$siteBaseUrl/downloads/$windowsInstallerFileName"
    sha256 = $windowsInstallerHash
    sizeMb = $windowsInstallerSizeMb
  }
} | ConvertTo-Json -Depth 4
Set-Content -LiteralPath (Join-Path $downloadsDir "latest.json") -Value $latestManifest -Encoding UTF8
$assetLinksJson = @"
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "$assetLinksPackageName",
      "sha256_cert_fingerprints": [
        "$assetLinksSha256"
      ]
    }
  }
]
"@
Set-Content -LiteralPath (Join-Path $wellKnownDir "assetlinks.json") -Value $assetLinksJson -Encoding ASCII

# Create a build manifest file to track versions
$buildTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$buildManifestLines = @(
  "=== The Vault Build Manifest ===",
  "Version: $versionDisplay",
  "Built: $buildTimestamp",
  "Semantic Version: $cleanVersion",
  "",
  "Android APK:",
  "  File: $apkFileName",
  "  Size: $apkSizeMb MB",
  "  SHA-256: $apkHash",
  "",
  "Windows Installer:",
  "  File: $windowsInstallerFileName",
  "  Size: $windowsInstallerSizeMb MB",
  "  SHA-256: $windowsInstallerHash"
)
$buildManifest = $buildManifestLines -join [Environment]::NewLine
$existingManifest = ""
$manifestPath = Join-Path $OutputDir "BUILD_MANIFEST.txt"
if (Test-Path $manifestPath) {
  $existingManifest = Get-Content -LiteralPath $manifestPath -Raw
}
if ([string]::IsNullOrWhiteSpace($existingManifest)) {
  Set-Content -LiteralPath $manifestPath -Value $buildManifest -Encoding UTF8
} else {
  Set-Content -LiteralPath $manifestPath -Value ($buildManifest + [Environment]::NewLine + $existingManifest.TrimStart()) -Encoding UTF8
}

Copy-Item -LiteralPath $privacyPath -Destination (Join-Path $OutputDir "privacy-policy.html")
Copy-Item -LiteralPath $termsPath -Destination (Join-Path $OutputDir "terms-of-service.html")
Copy-Item -LiteralPath $brandPath -Destination (Join-Path $OutputDir $brandOutputName)
Copy-Item -LiteralPath $faviconPath -Destination (Join-Path $OutputDir "favicon.png")

Write-Host "[OK] Vault download site built at $OutputDir"
Write-Host ""
Write-Host "Version: $versionDisplay"
Write-Host "Built: $buildTimestamp"
Write-Host ""
Write-Host "APK: $apkFileName"
Write-Host "  Size: $apkSizeMb MB"
Write-Host "  SHA-256: $apkHash"
Write-Host ""
Write-Host "Windows: $windowsInstallerFileName"
Write-Host "  Size: $windowsInstallerSizeMb MB"
Write-Host "  SHA-256: $windowsInstallerHash"
