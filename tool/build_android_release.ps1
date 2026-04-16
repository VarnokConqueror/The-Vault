param(
  [string]$RelayToken = "",
  [string]$RelayBaseUrl = "https://relay.theconquerorscourt.com",
  [string]$GiphyApiKey = "",
  [string]$GiphyRating = "",
  [switch]$BuildAppBundle,
  [switch]$AllowDebugReleaseSigning
)

$ErrorActionPreference = "Stop"

$repoRoot = "C:\Users\Varnok\The-Vault"
$iconScriptPath = Join-Path $repoRoot "tool\generate_app_icons.py"
$splashScriptPath = Join-Path $repoRoot "tool\generate_splash_assets.py"
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

if ([string]::IsNullOrWhiteSpace($resolvedRelayToken)) {
  throw "Relay token is required. Pass -RelayToken or set COURT_RELAY_TOKEN."
}

Push-Location $repoRoot
try {
  if (Test-Path $iconScriptPath) {
    & python $iconScriptPath
    if ($LASTEXITCODE -ne 0) {
      throw "Icon generation failed."
    }
  }

  if (Test-Path $splashScriptPath) {
    & python $splashScriptPath
    if ($LASTEXITCODE -ne 0) {
      throw "Splash generation failed."
    }
  }

  if ($AllowDebugReleaseSigning) {
    $env:ORG_GRADLE_PROJECT_VAULT_ALLOW_DEBUG_RELEASE_SIGNING = "true"
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

  & flutter build apk --release @dartDefines
  if ($LASTEXITCODE -ne 0) {
    throw "flutter build apk failed."
  }

  if ($BuildAppBundle) {
    & flutter build appbundle --release @dartDefines
    if ($LASTEXITCODE -ne 0) {
      throw "flutter build appbundle failed."
    }
  }
}
finally {
  if ($AllowDebugReleaseSigning) {
    Remove-Item Env:ORG_GRADLE_PROJECT_VAULT_ALLOW_DEBUG_RELEASE_SIGNING -ErrorAction SilentlyContinue
  }
  Pop-Location
}
