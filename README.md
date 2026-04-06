# Caldwell SYSPRO MCP Server

**Let your AI assistant query your SQL Server databases and SYSPRO system directly.**

Instead of copying data into prompts or describing your schema by hand, this MCP server gives Claude, Cursor, and Claude Code direct access to your databases — with read-only protection, credential isolation, and admin controls.

## What can you do with it?

Once installed and connected to your databases, you can ask your AI things like:

- *"What tables are in the SysproCompanyA database?"*
- *"Show me all outstanding purchase orders over $10,000"*
- *"Which tables contain customer code LON001?"*
- *"Query SYSPRO inventory for stock code A100"*
- *"Monitor blocking locks for the next 30 seconds"*
- *"Run the sql-health-check playbook"*
- *"Check if there's a newer version available"*

The AI reads your live data, understands your schema, and answers questions — no exports, no copy-paste.

## How does it work?

The MCP (Model Context Protocol) server runs alongside your AI client. When the AI needs data, it calls tools provided by this server — like `sql_query`, `sql_list_objects`, or `syspro_query`. Your database credentials are configured through a browser-based admin UI and are never visible to the AI.

## Is it safe?

- **Read-only by default** — queries are wrapped in a transaction that always rolls back, or validated against a read-only SQL user, or both
- **Credentials never exposed** — the AI sees aliases like "PROD-A", not connection strings or passwords
- **Row limits** — large result sets require explicit pagination
- **Object allowlisting** — restrict which tables/views the AI can see
- **Localhost admin UI** — configuration happens in your browser, not through the AI

## Install

**Windows** — open PowerShell and paste:

```powershell
irm https://raw.githubusercontent.com/mepapps/caldwell-syspro-mcp-releases/main/install.ps1 | iex
```

**Linux** — open a terminal and run:

```bash
curl -fsSL https://raw.githubusercontent.com/mepapps/caldwell-syspro-mcp-releases/main/install.sh | bash
```

Installs to `C:\Tools\caldwell-syspro-mcp\` (Windows) or `~/.local/share/caldwell-syspro-mcp/` (Linux). Takes about 30 seconds.

## Getting started

### 1. Register with your AI client

**Windows:** Double-click `register-mcp.cmd` in the install folder. It automatically finds and configures Claude Desktop, Cursor, and Claude Code.

**Linux:** The install script prints the JSON to add to your MCP client config.

### 2. Add your database connections

Open **http://localhost:5199** in your browser. The admin UI lets you:

- Enter your SQL Server details (server, database, auth type) — no connection strings to type
- Optionally configure SYSPRO e.net (server:port, operator, companies)
- Create a read-only SQL user with one click
- Test connectivity before saving

### 3. Restart your AI client

The server starts automatically when Claude, Cursor, or Claude Code connects.

### 4. Start asking questions

Try: *"What connections are available?"* — the AI will list your configured databases and you can start querying.

## What's included

| Capability | What it does |
|-----------|-------------|
| **SQL queries** | Run SELECT queries with pagination, batch queries, and monitoring polls |
| **Schema discovery** | Browse tables, columns, stored procedures, and database structure |
| **Key entity discovery** | Find which tables contain stock codes, customers, sales orders, etc. |
| **SYSPRO Business Objects** | Query, transact, and batch-operate via SYSPRO e.net REST API |
| **Playbooks** | Reusable step-by-step workflows (health checks, blocking analysis, etc.) |
| **Dev environments** | Provision isolated SQL Server environments from customer backups (optional) |
| **Admin UI** | Browser-based connection management at localhost:5199 |

## Updating

Double-click `update-single.cmd` in the install folder, or re-run the install command above.

## Links

- [All releases](https://github.com/mepapps/caldwell-syspro-mcp-releases/releases)
- [Full documentation](https://github.com/mepapps/Caldwell.syspro.mcp) — tool reference, configuration, architecture, building from source
