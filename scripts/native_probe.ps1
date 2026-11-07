$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
& python (Join-Path $PSScriptRoot 'native_probe.py')
if ($LASTEXITCODE -ne 0) {
    throw "Native external-process probe failed: $LASTEXITCODE"
}
