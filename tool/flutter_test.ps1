param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$FlutterTestArgs
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$unitTestAssetsDir = Join-Path $repoRoot 'build\unit_test_assets'

if (Test-Path $unitTestAssetsDir) {
  $lockCandidates = Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -in @('dart', 'dartaotruntime', 'flutter_tester') }

  foreach ($proc in $lockCandidates) {
    try {
      taskkill /F /PID $proc.Id | Out-Null
    } catch {
      # Best effort; test run can still continue.
    }
  }

  cmd /c "rmdir /s /q `"$unitTestAssetsDir`""
}

if ($FlutterTestArgs.Count -gt 0) {
  & flutter test @FlutterTestArgs
} else {
  & flutter test
}
