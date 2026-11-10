$ErrorActionPreference = 'Stop'
try {
    Write-Host 'Installing the tested SketchUp MCP connector...' -ForegroundColor Cyan
    $uv = Join-Path $env:USERPROFILE '.local\bin\uv.exe'
    if (!(Test-Path -LiteralPath $uv)) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $installerFile = Join-Path $PSScriptRoot 'install-uv.ps1'
        Invoke-WebRequest -UseBasicParsing -Uri 'https://astral.sh/uv/install.ps1' -OutFile $installerFile
        & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $installerFile
        if ($LASTEXITCODE -ne 0) { throw 'The uv installer failed.' }
    }
    if (!(Test-Path -LiteralPath $uv)) { throw 'uv was not installed in the expected location.' }
    & $uv python install 3.12
    if ($LASTEXITCODE -ne 0) { throw 'Python installation failed.' }
    & $uv tool install --python 3.12 --with 'mcp==1.3.0' --with 'pydantic==2.10.6' --with 'pydantic-settings==2.7.1' 'sketchup-mcp==0.1.17'
    if ($LASTEXITCODE -ne 0) { throw 'Connector installation failed.' }
    $binDir = (& $uv tool dir --bin | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Could not locate the installed connector.' }
    $connector = Join-Path $binDir 'sketchup-mcp.exe'
    if (!(Test-Path -LiteralPath $connector)) { throw 'Connector executable is missing.' }
    $cli = Get-Command codex.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
    if (!$cli) {
        $cli = Get-ChildItem -Path "$env:LOCALAPPDATA\OpenAI\Codex\bin\*\codex.exe" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
    if (!$cli) { throw 'Install or open Codex first, then rerun setup.' }
    & $cli mcp add sketchup -- $connector
    if ($LASTEXITCODE -ne 0) { throw 'Codex registration failed.' }
    & $cli mcp get sketchup
    if ($LASTEXITCODE -ne 0) { throw 'Codex did not find the registered connector.' }
    Write-Host 'Setup complete. Restart Codex after installing the shared SketchUp extension.'
} catch {
    Write-Host ('FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Take a screenshot of this window for troubleshooting.'
    exit 1
}

