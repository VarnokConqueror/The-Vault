param(
  [Parameter(Mandatory = $true)]
  [string]$ReleaseDir
)

$ErrorActionPreference = "Stop"

$repoRoot = "C:\Users\Varnok\The-Vault"
$helperProjectDir = Join-Path $repoRoot "windows\vault_bridge_helper"
$helperJarSource = Join-Path $helperProjectDir "build\libs\vault-bridge-helper-all.jar"
$jdkVendorRoot = Join-Path $repoRoot "tool\vendor\jdk"
$jdkExtractRoot = Join-Path $jdkVendorRoot "microsoft-jdk-21"
$jdkZipPath = Join-Path $jdkVendorRoot "microsoft-jdk-21-windows-x64.zip"
$jdkDownloadUrl = "https://aka.ms/download-jdk/microsoft-jdk-21-windows-x64.zip"

function Get-PortableJdkPath {
  $existing = Get-ChildItem -Path $jdkExtractRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    Select-Object -First 1
  if ($existing) {
    return $existing.FullName
  }

  New-Item -ItemType Directory -Force -Path $jdkVendorRoot | Out-Null
  Write-Host "Downloading portable JDK for Windows Vault helper..."
  Invoke-WebRequest -Uri $jdkDownloadUrl -OutFile $jdkZipPath

  if (Test-Path $jdkExtractRoot) {
    Remove-Item -Recurse -Force $jdkExtractRoot
  }
  Expand-Archive -Path $jdkZipPath -DestinationPath $jdkExtractRoot -Force

  $installed = Get-ChildItem -Path $jdkExtractRoot -Directory -ErrorAction Stop |
    Sort-Object Name -Descending |
    Select-Object -First 1
  if (-not $installed) {
    throw "Portable JDK extraction failed."
  }
  return $installed.FullName
}

function Ensure-Directory {
  param([string]$Path)
  New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

$jdkHome = Get-PortableJdkPath
$javaBinDir = Join-Path $jdkHome "bin"
$gradlePath = Join-Path $repoRoot "gradlew.bat"

if (-not (Test-Path $gradlePath)) {
  throw "gradlew.bat not found at $gradlePath"
}

$env:JAVA_HOME = $jdkHome
$env:PATH = "$javaBinDir;$env:PATH"

Write-Host "Building Windows Vault helper jar..."
& $gradlePath -p $helperProjectDir fatJar
if ($LASTEXITCODE -ne 0) {
  throw "Vault helper fatJar build failed."
}

if (-not (Test-Path $helperJarSource)) {
  throw "Helper jar not found at $helperJarSource"
}

$moduleDeps = & (Join-Path $javaBinDir "jdeps.exe") `
  --ignore-missing-deps `
  --print-module-deps `
  $helperJarSource

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($moduleDeps)) {
  $moduleDeps = "java.base,java.logging,jdk.crypto.ec,jdk.unsupported"
}

$runtimeDir = Join-Path $ReleaseDir "vault_runtime"
$helperStageDir = Join-Path $ReleaseDir "vault_bridge_helper"

if (Test-Path $runtimeDir) {
  Remove-Item -Recurse -Force $runtimeDir
}
if (Test-Path $helperStageDir) {
  Remove-Item -Recurse -Force $helperStageDir
}

Ensure-Directory -Path $helperStageDir

Write-Host "Creating portable runtime for Windows Vault helper..."
& (Join-Path $javaBinDir "jlink.exe") `
  --add-modules $moduleDeps `
  --output $runtimeDir `
  --strip-debug `
  --no-header-files `
  --no-man-pages

if ($LASTEXITCODE -ne 0) {
  throw "jlink runtime creation failed."
}

Copy-Item -LiteralPath $helperJarSource -Destination (Join-Path $helperStageDir "vault-bridge-helper-all.jar") -Force

Get-Item $runtimeDir, (Join-Path $helperStageDir "vault-bridge-helper-all.jar") |
  Select-Object FullName, Length, LastWriteTime
