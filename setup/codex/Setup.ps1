$ErrorActionPreference = 'Stop'
try {
    Write-Host 'Installing the tested SketchUp MCP connector...' -ForegroundColor Cyan
    $uv = Join-Path $env:USERPROFILE '.local\bin\uv.exe'
    if (!(Test-Path -LiteralPath $uv)) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        # Download the uv installer to the temp folder (not next to this script) and remove it afterwards.
        $installerFile = Join-Path ([IO.Path]::GetTempPath()) ('install-uv-' + [guid]::NewGuid().ToString('N') + '.ps1')
        try {
            Invoke-WebRequest -UseBasicParsing -Uri 'https://astral.sh/uv/install.ps1' -OutFile $installerFile
            & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $installerFile
            if ($LASTEXITCODE -ne 0) { throw 'The uv installer failed.' }
        } finally {
            Remove-Item -LiteralPath $installerFile -Force -ErrorAction SilentlyContinue
        }
    }
    if (!(Test-Path -LiteralPath $uv)) { throw 'uv was not installed in the expected location.' }
    # Only install Python when 3.12 is missing. Re-running "uv python install" while a connector
    # is running can fail halfway and break the existing Python link, so skip it when not needed.
    $ErrorActionPreference = 'Continue'
    & $uv python find 3.12 *> $null
    $havePython = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = 'Stop'
    if ($havePython) {
        Write-Host 'Python 3.12 is already installed'
    } else {
        & $uv python install 3.12
        if ($LASTEXITCODE -ne 0) { throw 'Python installation failed. Fully quit Claude and Codex (system tray > Quit), then rerun setup.' }
    }
    & $uv tool install --python 3.12 --with 'mcp==1.3.0' --with 'pydantic==2.10.6' --with 'pydantic-settings==2.7.1' 'sketchup-mcp==0.1.17'
    if ($LASTEXITCODE -ne 0) { throw 'Connector installation failed. Fully quit Claude and Codex (system tray > Quit), then rerun setup.' }
    $binDir = (& $uv tool dir --bin | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Could not locate the installed connector.' }
    $connector = Join-Path $binDir 'sketchup-mcp.exe'
    if (!(Test-Path -LiteralPath $connector)) { throw 'Connector executable is missing.' }
    $cli = Get-Command codex.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
    if (!$cli) {
        $cli = Get-ChildItem -Path "$env:LOCALAPPDATA\OpenAI\Codex\bin\*\codex.exe" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
    if (!$cli) {
        # Codex CLI installed with npm provides codex.cmd rather than codex.exe.
        $cli = Get-Command codex.cmd -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
    }
    if (!$cli) { throw 'Install or open Codex first, then rerun setup.' }
    & $cli mcp add sketchup -- $connector
    if ($LASTEXITCODE -ne 0) { throw 'Codex registration failed.' }
    & $cli mcp get sketchup
    if ($LASTEXITCODE -ne 0) { throw 'Codex did not find the registered connector.' }
    # "codex mcp add" writes only the command line, so add the settings it leaves out.
    # eval_ruby runs arbitrary Ruby under this Windows account, so it must stay behind an
    # approval prompt; without this block a fresh install would run it unprompted.
    $codexConfig = Join-Path $env:USERPROFILE '.codex\config.toml'
    if (Test-Path -LiteralPath $codexConfig) {
        $lines = New-Object 'Collections.Generic.List[string]'
        Get-Content -LiteralPath $codexConfig | ForEach-Object { $lines.Add($_) }
        $header = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim() -eq '[mcp_servers.sketchup]') { $header = $i; break }
        }
        if ($header -ge 0) {
            $end = $lines.Count
            for ($i = $header + 1; $i -lt $lines.Count; $i++) {
                if ($lines[$i].TrimStart().StartsWith('[')) { $end = $i; break }
            }
            $table = ''
            if ($end -gt ($header + 1)) { $table = ($lines[($header + 1)..($end - 1)]) -join "`n" }
            $insert = @()
            if ($table -notmatch '(?m)^\s*startup_timeout_sec\s*=') { $insert += 'startup_timeout_sec = 30' }
            if ($table -notmatch '(?m)^\s*tool_timeout_sec\s*=') { $insert += 'tool_timeout_sec = 120' }
            if ($insert.Count -gt 0) { $lines.InsertRange($header + 1, [string[]]$insert) }
        }
        if ((($lines) -join "`n") -notmatch '(?m)^\s*\[mcp_servers\.sketchup\.tools\.eval_ruby\]') {
            $lines.Add('')
            $lines.Add('[mcp_servers.sketchup.tools.eval_ruby]')
            $lines.Add('approval_mode = "approve"')
        }
        $codexStamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
        Copy-Item -LiteralPath $codexConfig -Destination ($codexConfig + '.backup-' + $codexStamp) -Force
        [IO.File]::WriteAllLines($codexConfig, $lines, (New-Object Text.UTF8Encoding($false)))
        Write-Host 'Added the eval_ruby approval prompt and connector timeouts.'
    } else {
        Write-Host 'WARNING: config.toml not found; eval_ruby will run without an approval prompt.' -ForegroundColor Yellow
    }
    Write-Host 'Setup complete. Restart Codex after installing the shared SketchUp extension.'
} catch {
    Write-Host ('FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Take a screenshot of this window for troubleshooting.'
    exit 1
}

