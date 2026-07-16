# AshitaDevTools

Local-only MCP bridge for Ashita addon development.

This repository is separate from `ashitamcp`. `ashitamcp` stays read-only. This project exists only to help with attended local addon development by exposing tightly restricted addon lifecycle tools and bounded local log reads.

## Safety Boundary

- The Ashita addon listens only on `127.0.0.1:19772`.
- The MCP server accepts only structured tool calls. It does not accept raw slash commands.
- Lifecycle requests can queue only these exact generated forms:
  - `/addon load <validated-name>`
  - `/addon unload <validated-name>`
  - `/addon reload <validated-name>`
- Addon names must match `^[A-Za-z0-9_-]+$` and are capped at 64 characters.
- One request performs at most one addon lifecycle operation.
- There is no generic `queue_command`, `run_command`, or slash-command endpoint.
- This must not be extended into gameplay commands or automation: no `/ma`, `/ja`, `/item`, `/target`, `/attack`, `/follow`, `/trade`, movement, inventory movement/use, buying, selling, packet injection, input simulation, timers, loops, game-state-triggered behavior, or detection-evasion behavior.
- Local log output can include private chat or other sensitive local context. Expose this only to trusted local MCP clients.

CatsEyeXI policy boundary: this is for attended addon development only. Check the CatsEyeXI addon policy before expanding AshitaCore behavior, and do not turn this bridge into gameplay automation or event-driven command execution.

## Layout

```text
ashitadevtools/                     Ashita addon
src/AshitaDevTools.Server/          .NET stdio MCP server
install.ps1                         Local addon installer
```

## Local Endpoint Contract

```text
GET  http://127.0.0.1:19772/status
GET  http://127.0.0.1:19772/ashita-log-tail?lines=100
POST http://127.0.0.1:19772/addon/load?name=<addon>
POST http://127.0.0.1:19772/addon/unload?name=<addon>
POST http://127.0.0.1:19772/addon/reload?name=<addon>
```

Lifecycle endpoints require `POST`. A browser `GET` cannot load, unload, or reload an addon.

The Lua addon includes an empty `allowed_addons` table. Empty means any name that passes strict validation is allowed. To restrict operations further, add explicit local development addon names to that table before installing the addon.

## Install Addon

From this repository:

```powershell
.\install.ps1
```

In game:

```text
/addon load ashitadevtools
/adt status
```

Manual endpoint checks:

```powershell
Invoke-RestMethod http://127.0.0.1:19772/status
Invoke-RestMethod 'http://127.0.0.1:19772/ashita-log-tail?lines=25'
Invoke-RestMethod -Method Post 'http://127.0.0.1:19772/addon/reload?name=ashitadevtools'
```

## Run MCP Server Manually

Build first, then run the built DLL so restore/build output cannot interfere with MCP stdio protocol messages:

```powershell
dotnet build .\src\AshitaDevTools.Server\AshitaDevTools.Server.csproj
dotnet .\src\AshitaDevTools.Server\bin\Debug\net10.0\AshitaDevTools.Server.dll
```

Override the endpoint only with another `127.0.0.1` URL:

```text
ASHITADEVTOOLS_BASE_URL=http://127.0.0.1:19772
```

The MCP server rejects non-`127.0.0.1` base URLs.

## MCP Tools

- `devtools_status` - returns local bridge status without running lifecycle operations.
- `addon_load(name)` - queues exactly one `/addon load <validated-name>`.
- `addon_unload(name)` - queues exactly one `/addon unload <validated-name>`.
- `addon_reload(name)` - queues exactly one `/addon reload <validated-name>`.
- `ashita_log_tail(lines = 100)` - returns a bounded tail of the current character's local Ashita chat log.

Manual MCP checks after loading the addon in game:

```text
devtools_status
ashita_log_tail(lines = 25)
addon_reload(name = "ashitadevtools")
addon_load(name = "../bad")      # should be rejected by validation
addon_unload(name = "/ma")       # should be rejected by validation
```

Example MCP client shape:

```json
{
  "mcpServers": {
    "ashitadevtools": {
      "command": "dotnet",
      "args": [
        "<workspace-root>\\ashitadevtools\\src\\AshitaDevTools.Server\\bin\\Debug\\net10.0\\AshitaDevTools.Server.dll"
      ]
    }
  }
}
```

## Build

```powershell
dotnet build .\src\AshitaDevTools.Server\AshitaDevTools.Server.csproj
```
