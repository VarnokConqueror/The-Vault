Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$webSource = Join-Path $repoRoot "web"
$buildOutput = Join-Path $repoRoot "build\web"
$privacySource = Join-Path $webSource "privacy-policy.html"
$privacyTarget = Join-Path $buildOutput "privacy-policy.html"
$termsSource = Join-Path $webSource "terms-of-service.html"
$termsTarget = Join-Path $buildOutput "terms-of-service.html"

Push-Location $repoRoot
try {
    flutter build web

    if (-not (Test-Path $privacySource)) {
        throw "Missing privacy page source at $privacySource"
    }
    if (-not (Test-Path $termsSource)) {
        throw "Missing terms page source at $termsSource"
    }

    Copy-Item -LiteralPath $privacySource -Destination $privacyTarget -Force
    Copy-Item -LiteralPath $termsSource -Destination $termsTarget -Force
    Write-Host "Copied privacy-policy.html to $privacyTarget"
    Write-Host "Copied terms-of-service.html to $termsTarget"
}
finally {
    Pop-Location
}
