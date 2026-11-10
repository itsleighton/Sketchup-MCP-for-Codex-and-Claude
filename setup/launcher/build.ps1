# Builds dist\Setup-Claude.exe and dist\Setup-Codex.exe from Launcher.cs, embedding the
# matching Setup.ps1. Uses the C# compiler that ships with .NET Framework 4 on Windows.
# Run from any folder:  powershell -NoProfile -ExecutionPolicy Bypass -File setup\launcher\build.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (!(Test-Path -LiteralPath $csc)) { throw "C# compiler not found at $csc" }
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null

foreach ($app in 'Claude', 'Codex') {
    $script = Join-Path $root ("setup\" + $app.ToLower() + "\Setup.ps1")
    $out = Join-Path $dist ("Setup-$app.exe")
    & $csc /nologo /target:exe /platform:anycpu /optimize+ "/out:$out" "/resource:$script,Setup.ps1" (Join-Path $PSScriptRoot 'Launcher.cs')
    if ($LASTEXITCODE -ne 0) { throw "Build failed for $app" }
    Write-Host "Built $out"
}
