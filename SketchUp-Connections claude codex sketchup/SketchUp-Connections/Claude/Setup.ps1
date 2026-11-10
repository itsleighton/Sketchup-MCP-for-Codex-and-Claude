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
    $configs = @()
    $localRoot = Join-Path $env:LOCALAPPDATA 'Claude-Data'
    if (Test-Path -LiteralPath $localRoot) {
        $configs = @(Get-ChildItem -LiteralPath $localRoot -Directory | ForEach-Object {
            $candidate = Join-Path $_.FullName 'claude_desktop_config.json'
            if (Test-Path -LiteralPath $candidate) { $candidate }
        })
    }
    if ($configs.Count -gt 1) { throw 'Multiple Claude profiles found. Setup stopped without changing files; ask for help selecting the active profile.' }
    if ($configs.Count -eq 1) { $configPath = $configs[0] }
    else {
        $configPath = Join-Path $env:APPDATA 'Claude\claude_desktop_config.json'
        if (!(Test-Path -LiteralPath $configPath)) { throw 'Open Claude Desktop, click Settings > Desktop app > Extensions > Edit config once, then fully quit Claude and rerun this installer.' }
    }
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    if ($null -eq $config) { throw 'Claude configuration is empty. Open Edit config in Claude first.' }
    if (!$config.PSObject.Properties['mcpServers']) { $config | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{}) }
    if ($null -eq $config.mcpServers) { $config.mcpServers = [pscustomobject]@{} }
    $entry = [pscustomobject]@{ command = $connector; args = @() }
    $config.mcpServers | Add-Member -NotePropertyName sketchup -NotePropertyValue $entry -Force
    $json = $config | ConvertTo-Json -Depth 100
    $null = $json | ConvertFrom-Json
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    

    $pending = $configPath + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($pending, $json, (New-Object Text.UTF8Encoding($false)))
    [IO.File]::Replace($pending, $configPath, ($configPath + '.backup-' + $stamp))
    Write-Host 'Setup complete. Restart Claude after installing the shared SketchUp extension.'
} catch {
    Write-Host ('FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Take a screenshot of this window for troubleshooting.'
    exit 1
}

