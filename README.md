# SketchUp MCP for Claude and Codex (Windows)

Lets an AI app — **Claude Desktop** or **OpenAI Codex** — read and draw in SketchUp on your
Windows PC through the [Model Context Protocol](https://modelcontextprotocol.io) (MCP).

> ⚠️ **Security — read this first.** While the SketchUp server is running, *any program on your PC*
> can send it commands, with no password, including `eval_ruby`, which runs arbitrary Ruby code
> under your Windows account (it can read, change or delete your files). The server only listens on
> `127.0.0.1`, so other computers can't reach it. Start the server only while you're using it, and
> stop it when you're done. Anything the AI reads from your model becomes part of that AI chat.

## How it fits together

| Part | What it is | Installed by |
|---|---|---|
| **SketchUp extension** | Ruby code inside SketchUp. Listens on `127.0.0.1:9876` after *Start Server*. | `SketchUp-MCP.rbz` |
| **Connector** (`sketchup-mcp.exe`) | One shared program the AI app starts; it relays between the app and SketchUp. Downloaded from PyPI ([`sketchup-mcp` 0.1.17](https://pypi.org/project/sketchup-mcp/0.1.17/)). | Either setup EXE |
| **Claude registration** | An entry in `%APPDATA%\Claude\claude_desktop_config.json` | `Setup-Claude.exe` |
| **Codex registration** | An entry in `%USERPROFILE%\.codex\config.toml` | `Setup-Codex.exe` |

Claude and Codex share the same connector and the same SketchUp extension. Run one setup or both.

## Install

Download the files from the [Releases](../../releases) page:
`SketchUp-MCP.rbz`, plus `Setup-Claude.exe` and/or `Setup-Codex.exe`.

1. **SketchUp:** *Extensions > Extension Manager > Install Extension*, choose `SketchUp-MCP.rbz`,
   then restart SketchUp.
2. **Fully quit Claude and Codex** — right-click each tray icon > *Quit*. (Closing the window isn't
   enough; a running connector can block the install.)
3. **Claude:** open Claude once, go to *Settings > Desktop app > Extensions > Edit config* (this creates
   the config file), fully quit Claude again, then run **`Setup-Claude.exe`**.
4. **Codex:** install and open Codex at least once, quit it, then run **`Setup-Codex.exe`**.
5. Each setup window should end with **"Setup complete."** Press Enter to close it.

**"Windows protected your PC"?** The EXEs aren't code-signed, so SmartScreen warns. Click
*More info > Run anyway*, or skip the EXEs and run the scripts instead (see below).

Setup needs internet access. It installs, for your user only (no admin rights):
[uv](https://docs.astral.sh/uv/) (if missing), Python 3.12 (if missing), and the connector.

## Use

1. In SketchUp: **Extensions > MCP Server > Start Server**. A small status light shows
   LISTENING (amber) or ACTIVE (green). While active it also names the app that's talking to
   SketchUp, e.g. `Claude - 3s ago` or `Claude + Codex - 3s ago`. Hover the light, or click the
   **MCP Info** toolbar button, for request counts per app.
2. Open Claude or Codex and start a **new chat**. Try: *"What's selected in SketchUp?"*
3. When finished: **Extensions > MCP Server > Stop Server**.

### Which app is Codex?

OpenAI's Codex desktop app appears in the Windows Start menu as **"ChatGPT"**. The older app named
**"ChatGPT Classic"** is regular ChatGPT; it runs chats in the cloud and **can't** use this
connector. In Codex, make sure the chat runs **locally**, not in the cloud.

## Tools available to the AI

`create_component`, `delete_component`, `transform_component`, `get_selection`, `set_material`,
`export_scene`, `create_mortise_tenon`, `create_dovetail`, `create_finger_joint`, `eval_ruby`.

### How SketchUp knows which app is connected

Requests don't carry an app name, so the extension asks Windows which process owns each incoming
connection and follows its parent processes: `sketchup-mcp.exe` started by `claude.exe` shows as
**Claude**, by `codex.exe` as **Codex**. A connector started by another app shows as
`Other (app.exe)`; anything else (e.g. a script talking to port 9876 directly) shows as
**Unknown**. It identifies the app, not the chat or the person. The lookup uses built-in Windows
APIs, runs once per connector process, and never blocks a request (on failure it reports
Unknown).

## Troubleshooting

| Symptom | Fix |
|---|---|
| The AI says it has no SketchUp tools | Fully quit and reopen the app (tray > Quit), then start a new chat. For Codex, check you opened **"ChatGPT"** (not Classic) and the chat is local. |
| "Communication error with SketchUp" | In SketchUp, choose *Start Server*. Check the status light. |
| Setup says "Access is denied" or "being used by another process" | Claude or Codex is still running a connector. Quit both from the tray (or restart the PC) and rerun setup. |
| "Multiple Claude profiles found" | The Claude setup stops without changing anything; edit the right `claude_desktop_config.json` by hand (see below). |

## Uninstall

1. Fully quit Claude and Codex.
2. Remove the connector: `& "$env:USERPROFILE\.local\bin\uv.exe" tool uninstall sketchup-mcp`
3. Codex: `codex mcp remove sketchup` (use `codex.cmd` in Windows PowerShell if scripts are blocked).
4. Claude: open `%APPDATA%\Claude\claude_desktop_config.json` and delete the `"sketchup"` entry
   under `"mcpServers"`.
5. SketchUp: *Extension Manager* > *MCP Server* > *Uninstall*.

## Running the scripts instead of the EXEs

Each EXE just runs its embedded script. To run a script directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File setup\claude\Setup.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File setup\codex\Setup.ps1
```

## Repository layout

```
extension/            SketchUp extension source (packed into SketchUp-MCP.rbz)
  su_mcp.rb             extension loader
  su_mcp/main.rb        MCP server inside SketchUp
  su_mcp/client_identity.rb  identifies which app (Claude/Codex) owns a connection
  mcp_status_monitor.rb status-light panel and toolbar
setup/claude/Setup.ps1  installs connector + registers it with Claude Desktop
setup/codex/Setup.ps1   installs connector + registers it with Codex
setup/launcher/         C# source for the setup EXEs, and build.ps1
dist/                   built files to attach to a GitHub Release (not committed)
```

## Building the release files

```powershell
# EXEs (uses the C# compiler included with Windows' .NET Framework 4)
powershell -NoProfile -ExecutionPolicy Bypass -File setup\launcher\build.ps1
```

`SketchUp-MCP.rbz` is a zip of the `extension/` folder's contents (`su_mcp.rb`, `su_mcp/` with
`main.rb` and `client_identity.rb`,
`mcp_status_monitor.rb`, `mcp_status_monitor/`) renamed to `.rbz`. Rebuild the EXEs whenever a
`Setup.ps1` changes — each EXE carries its own copy of the script.

## Changes from the original project

- **SketchUp no longer freezes on a silent connection.** The original server waited, with no time
  limit, for each client to send its request, blocking SketchUp's UI. It now reads clients without
  blocking and drops any that send nothing within 5 seconds.
- **Setup skips installing Python when 3.12 is already present.** Reinstalling while a connector was
  running could fail halfway and break the existing Python install.
- The uv installer is downloaded to the temp folder and deleted afterwards.
- The Codex setup also finds a Codex CLI installed with npm (`codex.cmd`).
- Added the status-light panel (`mcp_status_monitor.rb`).
- **The status light shows which app is talking to SketchUp** (Claude, Codex, or Unknown), with
  per-app request counts in the tooltip and the MCP Info dialog.

## Credits and license

Built on the open-source `sketchup-mcp` project (MIT License); the connector is installed unmodified
from PyPI. See [LICENSE](LICENSE).
