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

# Packs extension\ into dist\SketchUp-MCP.rbz (an .rbz is a renamed .zip). Entries are added
# one by one with forward slashes: ZipFile::CreateFromDirectory writes backslashes on .NET
# Framework, which is invalid per the ZIP spec and can flatten su_mcp\ into a literal name.
$ext = Join-Path $root 'extension'
if (!(Test-Path -LiteralPath $ext)) { throw "Extension source not found at $ext" }
$rbz = Join-Path $dist 'SketchUp-MCP.rbz'
if (Test-Path -LiteralPath $rbz) { Remove-Item -LiteralPath $rbz -Force }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::Open($rbz, [IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem -LiteralPath $ext -Recurse -File | Sort-Object FullName | ForEach-Object {
        $entry = $_.FullName.Substring($ext.Length + 1).Replace("\", "/")
        $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $entry)
    }
} finally {
    $zip.Dispose()
}
Write-Host "Built $rbz"
