param(
  [string]$OutputDir = "C:\Users\Varnok\The-Vault\build\vault-download-site",
  [string]$ApkPath = "C:\Users\Varnok\The-Vault\build\app\outputs\flutter-apk\app-release.apk",
  [string]$WindowsInstallerPath = "",
  [string]$DonateUrl = "https://www.paypal.com/biz/profile/varnoksystemsllc",
  [string]$RemoteUser = "root",
  [string]$RemoteHost = "138.197.89.148",
  [string]$RemotePath = "/var/www/vault.theconquerorscourt.com",
  [string]$SiteUrl = "https://vault.theconquerorscourt.com",
  [string]$SshKeyPath = "$env:USERPROFILE\.ssh\id_ed25519",
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

function Invoke-ExternalCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [Parameter(Mandatory = $true)]
    [string[]]$ArgumentList
  )

  & $FilePath @ArgumentList
  if ($LASTEXITCODE -ne 0) {
    $joinedArguments = $ArgumentList -join " "
    throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $joinedArguments"
  }
}

$repoRoot = "C:\Users\Varnok\The-Vault"
$buildScriptPath = Join-Path $repoRoot "tool\build_vault_download_site.ps1"
$pubspecPath = Join-Path $repoRoot "pubspec.yaml"
$scpPath = (Get-Command scp.exe -ErrorAction Stop).Source
$sshPath = (Get-Command ssh.exe -ErrorAction Stop).Source

if (-not (Test-Path -LiteralPath $buildScriptPath)) {
  throw "Build script not found at $buildScriptPath"
}

if (-not (Test-Path -LiteralPath $SshKeyPath)) {
  throw "SSH key not found at $SshKeyPath"
}

if (-not $SkipBuild) {
  Write-Host "[STEP] Building vault download site bundle..."
  $buildArguments = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $buildScriptPath,
    "-OutputDir", $OutputDir,
    "-ApkPath", $ApkPath,
    "-DonateUrl", $DonateUrl
  )

  if (-not [string]::IsNullOrWhiteSpace($WindowsInstallerPath)) {
    $buildArguments += @("-WindowsInstallerPath", $WindowsInstallerPath)
  }

  Invoke-ExternalCommand -FilePath "powershell.exe" -ArgumentList $buildArguments
}

if (-not (Test-Path -LiteralPath $OutputDir)) {
  throw "Output directory not found at $OutputDir"
}

$versionLine = (Get-Content -LiteralPath $pubspecPath | Select-String '^version:\s*(.+)$' | Select-Object -First 1).Matches[0].Groups[1].Value.Trim()
$versionParts = $versionLine -split '\+'
$semanticVersion = $versionParts[0]
$apkFileName = "the-vault-android-v${semanticVersion}.apk"
$windowsInstallerFileName = "the-vault-windows-setup-v${semanticVersion}.exe"
$apkShaFileName = "$apkFileName.sha256.txt"
$windowsShaFileName = "$windowsInstallerFileName.sha256.txt"

Write-Host "[STEP] Ensuring remote target exists..."
Invoke-ExternalCommand -FilePath $sshPath -ArgumentList @(
  "-i", $SshKeyPath,
  "-o", "StrictHostKeyChecking=no",
  "$RemoteUser@$RemoteHost",
  "mkdir -p '$RemotePath'"
)

Write-Host "[STEP] Clearing remote target contents..."
Invoke-ExternalCommand -FilePath $sshPath -ArgumentList @(
  "-i", $SshKeyPath,
  "-o", "StrictHostKeyChecking=no",
  "$RemoteUser@$RemoteHost",
  "find '$RemotePath' -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +"
)

Write-Host "[STEP] Uploading vault download site..."
$uploadItems = Get-ChildItem -Force -LiteralPath $OutputDir
if ($uploadItems.Count -eq 0) {
  throw "No files found to upload from $OutputDir"
}
foreach ($uploadItem in $uploadItems) {
  Invoke-ExternalCommand -FilePath $scpPath -ArgumentList @(
    "-i", $SshKeyPath,
    "-r",
    "-o", "StrictHostKeyChecking=no",
    $uploadItem.FullName,
    "${RemoteUser}@${RemoteHost}:$RemotePath/"
  )
}

Write-Host "[STEP] Normalizing remote permissions..."
Invoke-ExternalCommand -FilePath $sshPath -ArgumentList @(
  "-i", $SshKeyPath,
  "-o", "StrictHostKeyChecking=no",
  "$RemoteUser@$RemoteHost",
  "find '$RemotePath' -type d -exec chmod 755 {} + && find '$RemotePath' -type f -exec chmod 644 {} +"
)

Write-Host "[STEP] Verifying live site..."
$homepageHeaders = curl.exe -sS -I -L -A "Mozilla/5.0" $SiteUrl
$homepageHeadersText = $homepageHeaders -join "`n"
if ($LASTEXITCODE -ne 0 -or ($homepageHeadersText -notmatch '200 OK')) {
  throw "Homepage verification failed for $SiteUrl"
}

$homepageContent = curl.exe -sS -L -A "Mozilla/5.0" $SiteUrl
$homepageContentText = $homepageContent -join "`n"
if ($LASTEXITCODE -ne 0) {
  throw "Failed to fetch homepage content from $SiteUrl"
}
if ($homepageContentText -notmatch [regex]::Escape($semanticVersion)) {
  throw "Homepage does not include expected version $semanticVersion"
}
if ($homepageContentText -notmatch [regex]::Escape($apkFileName)) {
  throw "Homepage does not reference expected APK $apkFileName"
}
if ($homepageContentText -notmatch [regex]::Escape($windowsInstallerFileName)) {
  throw "Homepage does not reference expected Windows installer $windowsInstallerFileName"
}

foreach ($assetPath in @(
  "$SiteUrl/.well-known/assetlinks.json",
  "$SiteUrl/downloads/$apkShaFileName",
  "$SiteUrl/downloads/$windowsShaFileName",
  "$SiteUrl/downloads/$windowsInstallerFileName"
)) {
  $assetHeaders = curl.exe -sS -I -L -A "Mozilla/5.0" $assetPath
  $assetHeadersText = $assetHeaders -join "`n"
  if ($LASTEXITCODE -ne 0 -or ($assetHeadersText -notmatch '200 OK')) {
    throw "Asset verification failed for $assetPath"
  }
}

$assetLinksUrl = "$SiteUrl/.well-known/assetlinks.json"
$assetLinksContent = curl.exe -sS -L -A "Mozilla/5.0" $assetLinksUrl
$assetLinksContentText = $assetLinksContent -join "`n"
if ($LASTEXITCODE -ne 0) {
  throw "Failed to fetch asset links content from $assetLinksUrl"
}
if ($assetLinksContentText -notmatch '"delegate_permission/common.handle_all_urls"' -or
    $assetLinksContentText -notmatch '"package_name":\s*"com\.theconquerorscourt\.vault"') {
  throw "Asset links content is missing the expected Android app association."
}

Write-Host "[OK] Vault download site deployed successfully."
Write-Host "  Version: $semanticVersion"
Write-Host "  Site: $SiteUrl"
Write-Host "  APK: $SiteUrl/downloads/$apkFileName"
Write-Host "  Windows: $SiteUrl/downloads/$windowsInstallerFileName"
