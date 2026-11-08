$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
  python scripts/cli_smoke.py
  if ($LASTEXITCODE -ne 0) { throw "CLI smoke failed (exit $LASTEXITCODE)" }
} finally { Pop-Location }
