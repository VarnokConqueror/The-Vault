param(
  [switch]$SkipWindowsBuild,
  [string]$RelayToken = "",
  [string]$RelayBaseUrl = "https://relay.theconquerorscourt.com",
  [string]$GiphyApiKey = "",
  [string]$GiphyRating = "",
  [string]$SigningCertificatePfx = "",
  [string]$SigningCertificatePassword = "",
  [string]$SigningTimestampServer = "http://timestamp.digicert.com",
  [string]$OutputInstallerPath = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = "C:\Users\Varnok\The-Vault"
$releaseDir = Join-Path $repoRoot "build\windows\x64\runner\Release"
$distDir = Join-Path $repoRoot "build\dist"
$issPath = Join-Path $repoRoot "installer\windows\the_vault.iss"
$pubspecPath = Join-Path $repoRoot "pubspec.yaml"
$iconScriptPath = Join-Path $repoRoot "tool\generate_app_icons.py"
$helperBuildScriptPath = Join-Path $repoRoot "tool\build_windows_vault_bridge_helper.ps1"
$isccPath = "C:\Users\Varnok\AppData\Local\Programs\Inno Setup 6\ISCC.exe"

function Get-IsccPath {
  if (Test-Path $isccPath) {
    return $isccPath
  }

  $found = Get-Command iscc.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($found) {
    return $found.Source
  }

  $fallbacks = @(
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe"
  )
  foreach ($candidate in $fallbacks) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  return $null
}

function Get-SigntoolPath {
  $signtool = Get-Command signtool.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($signtool) {
    return $signtool.Source
  }

  $fallbacks = @(
    "C:\Program Files (x86)\Windows Kits\10\bin\x64\signtool.exe",
    "C:\Program Files\Windows Kits\10\bin\x64\signtool.exe",
    "C:\Program Files (x86)\Windows Kits\8.1\bin\x64\signtool.exe",
    "C:\Program Files\Windows Kits\8.1\bin\x64\signtool.exe"
  )
  foreach ($candidate in $fallbacks) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  return $null
}

function Sign-File {
  param(
    [string]$ToolPath,
    [string]$TargetFile
  )

  if (-not (Test-Path $TargetFile)) {
    throw "File not found for signing: $TargetFile"
  }

  if (-not (Test-Path $SigningCertificatePfx)) {
    throw "Signing certificate not found: $SigningCertificatePfx"
  }

  $arguments = @(
    'sign',
    '/f', $SigningCertificatePfx,
    '/p', $SigningCertificatePassword,
    '/tr', $SigningTimestampServer,
    '/td', 'sha256',
    '/fd', 'sha256',
    '/a',
    $TargetFile
  )

  Write-Host "Signing $TargetFile using certificate $SigningCertificatePfx"
  & $ToolPath @arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Signer failed for $TargetFile"
  }
}

function Sign-With-Authenticode {
  param(
    [string]$TargetFile
  )

  if (-not (Test-Path $TargetFile)) {
    throw "File not found for signing: $TargetFile"
  }

  if (-not (Test-Path $SigningCertificatePfx)) {
    throw "Signing certificate not found: $SigningCertificatePfx"
  }

  $cert = $null
  if ([string]::IsNullOrWhiteSpace($SigningCertificatePassword)) {
    $cert = Get-PfxCertificate -FilePath $SigningCertificatePfx
  } else {
    # Load certificate with password using .NET
    $pfxBytes = [System.IO.File]::ReadAllBytes($SigningCertificatePfx)
    $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($pfxBytes, $SigningCertificatePassword)
  }
  if (-not $cert) {
    throw "Unable to load signing certificate from $SigningCertificatePfx"
  }

  Write-Host "Signing $TargetFile with Set-AuthenticodeSignature"
  $signature = Set-AuthenticodeSignature -FilePath $TargetFile -Certificate $cert -TimestampServer $SigningTimestampServer
  if ($signature.Status -ne 'Valid') {
    throw "Authenticode signature failed for $TargetFile" + ": " + $signature.StatusMessage
  }
}

$isccPath = Get-IsccPath
if (-not $isccPath) {
  throw "ISCC.exe not found. Install Inno Setup 6 or put iscc.exe on PATH."
}

if (Test-Path $iconScriptPath) {
  python $iconScriptPath
}

$resolvedRelayToken = if ([string]::IsNullOrWhiteSpace($RelayToken)) {
  $env:COURT_RELAY_TOKEN
} else {
  $RelayToken
}
$resolvedGiphyApiKey = if ([string]::IsNullOrWhiteSpace($GiphyApiKey)) {
  $env:VAULT_GIPHY_API_KEY
} else {
  $GiphyApiKey
}
$resolvedGiphyRating = if ([string]::IsNullOrWhiteSpace($GiphyRating)) {
  $env:VAULT_GIPHY_RATING
} else {
  $GiphyRating
}

if (-not $SkipWindowsBuild) {
  if ([string]::IsNullOrWhiteSpace($resolvedRelayToken)) {
    throw "Relay token is required. Pass -RelayToken or set COURT_RELAY_TOKEN."
  }
  $dartDefines = @(
    "--dart-define=RELAY_TOKEN_ENABLED=true",
    "--dart-define=RELAY_TOKEN=$resolvedRelayToken",
    "--dart-define=RELAY_BASE_URL=$RelayBaseUrl"
  )
  if (-not [string]::IsNullOrWhiteSpace($resolvedGiphyApiKey)) {
    $dartDefines += "--dart-define=GIPHY_API_KEY=$resolvedGiphyApiKey"
  }
  if (-not [string]::IsNullOrWhiteSpace($resolvedGiphyRating)) {
    $dartDefines += "--dart-define=GIPHY_RATING=$resolvedGiphyRating"
  }

  & flutter build windows --release @dartDefines
  if ($LASTEXITCODE -ne 0) {
    throw "flutter build windows failed."
  }
}

if (-not (Test-Path (Join-Path $releaseDir "the_vault.exe"))) {
  throw "Windows release build not found at $releaseDir"
}

if (Test-Path $helperBuildScriptPath) {
  & powershell -ExecutionPolicy Bypass -File $helperBuildScriptPath -ReleaseDir $releaseDir
  if ($LASTEXITCODE -ne 0) {
    throw "Windows Vault helper staging failed."
  }
}

$versionLine = (Get-Content -LiteralPath $pubspecPath | Select-String '^version:\s*(.+)$' | Select-Object -First 1)
if (-not $versionLine) {
  throw "Could not read version from pubspec.yaml"
}

$versionRaw = $versionLine.Matches[0].Groups[1].Value.Trim()
$parts = $versionRaw -split '\+'
$appVersion = $parts[0]
$buildNumber = if ($parts.Length -gt 1) { $parts[1] } else { "0" }

if (Test-Path $distDir) {
  Get-ChildItem -Path $distDir -Filter "the-vault-windows-setup-*.exe" -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
}
New-Item -ItemType Directory -Force -Path $distDir | Out-Null

$envCertPath = $env:VAULT_WINDOWS_SIGNING_CERT
if ([string]::IsNullOrWhiteSpace($SigningCertificatePfx) -and -not [string]::IsNullOrWhiteSpace($envCertPath)) {
  $SigningCertificatePfx = $envCertPath
}
$defaultSigningCert = Get-ChildItem -Path $distDir -Filter 'vault-selfsigned*.pfx' -ErrorAction SilentlyContinue | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($SigningCertificatePfx) -and $defaultSigningCert) {
  $SigningCertificatePfx = $defaultSigningCert.FullName
}
$defaultSigningCertificatePassword = 'VaultSelfSigned2026!'
if (-not [string]::IsNullOrWhiteSpace($SigningCertificatePfx) -and [string]::IsNullOrWhiteSpace($SigningCertificatePassword)) {
  $SigningCertificatePassword = $defaultSigningCertificatePassword
}

& $isccPath `
  "/DMyAppVersion=$appVersion" `
  "/DMyBuildNumber=$buildNumber" `
  "/DMySourceDir=$releaseDir" `
  "/DMyOutputDir=$distDir" `
  $issPath

$defaultInstallerPath = Join-Path $distDir "the-vault-windows-setup-v$appVersion.exe"
$installerPath = if (-not [string]::IsNullOrWhiteSpace($OutputInstallerPath)) {
  $OutputInstallerPath
} else {
  $defaultInstallerPath
}

if (-not (Test-Path $installerPath)) {
  throw "Expected installer was not created: $installerPath"
}

if (-not [string]::IsNullOrWhiteSpace($SigningCertificatePfx)) {
  $releaseExe = Join-Path $releaseDir "the_vault.exe"
  $signtoolPath = Get-SigntoolPath

  if ($signtoolPath) {
    if (Test-Path $releaseExe) {
      Sign-File -ToolPath $signtoolPath -TargetFile $releaseExe
    }
    Sign-File -ToolPath $signtoolPath -TargetFile $installerPath
  } else {
    Write-Host "signtool.exe not found; falling back to Set-AuthenticodeSignature"
    if (Test-Path $releaseExe) {
      Sign-With-Authenticode -TargetFile $releaseExe
    }
    Sign-With-Authenticode -TargetFile $installerPath
  }

  Write-Host "Signed installer and executable with $SigningCertificatePfx"
}

Get-Item $installerPath | Select-Object FullName, Length, LastWriteTime
