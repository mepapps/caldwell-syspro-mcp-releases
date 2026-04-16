# Caldwell SYSPRO MCP Server

Gives AI assistants (Claude, Cursor, etc.) safe access to your SQL databases and SYSPRO Business Objects.

## Install

Open **PowerShell** and paste this:

```powershell
irm https://raw.githubusercontent.com/mepapps/caldwell-syspro-mcp-releases/main/install.ps1 | iex
```

This installs to `C:\Tools\caldwell-syspro-mcp\` and takes about 30 seconds.

## After Install

1. **Register with your AI client** — double-click `register-mcp.cmd` in the install folder. It automatically configures Claude Desktop, Cursor, and Claude Code.

2. **Add your database connections** — open `http://localhost:5199` in your browser (the admin UI starts automatically with the server). Fill in your SQL Server details — no connection strings to type, no JSON to edit.

3. **Restart your AI client** — the server starts automatically when Claude/Cursor connects.

## That's it

Ask your AI: *"What connections are available?"* — it will list your configured databases.

## Updating

Double-click `update-single.cmd` in the install folder. It downloads the latest version and replaces the exe automatically.

## Links

- [All releases](https://github.com/mepapps/caldwell-syspro-mcp-releases/releases)
- [Documentation](https://github.com/mepapps/Caldwell.syspro.mcp)
