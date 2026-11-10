1. Extract the ZIP on the target Windows PC.
2. Install SketchUp Extension\SketchUp-MCP.rbz through SketchUp Extension Manager. Restart SketchUp.
3. For Claude, open Edit config once, fully quit Claude, then run Claude\Setup-Claude.exe. For Codex, install Codex and run Codex\Setup-Codex.exe. Run both to configure both clients.
4. In SketchUp choose Extensions > MCP Server > Start Server. Reopen your chosen client.
5. Use Stop Server when finished. The server accepts local commands without authentication, including arbitrary Ruby under your user account. Keep port 9876 local. Model information requested by an AI client can enter that client's conversation.
Internet is required for dependencies. The EXEs are unsigned. The Ruby folder contains the packaged extension source and toolbar icons.
