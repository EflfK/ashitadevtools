# AshitaDevTools Repository Context

This repository contains a local-only Ashita addon development MCP bridge.

Workspace layout:

Relative to the root `FinalFantasyXI` workspace directory:

- `FinalFantasyXI/` is the personal CatsEyeXI playthrough/docs repository.
- `ashitamcp/` is the separate read-only MCP bridge. Keep it read-only.
- `ashitadevtools/` is this repository: `EflfK/ashitadevtools`.
- `ashitastreamdeck/` is the attended Stream Deck/Ashita bridge repository.

Safety boundary:

- This project is a dev-only bridge for local Ashita addon lifecycle work.
- The Ashita addon must listen only on `127.0.0.1`.
- Do not add arbitrary command execution or a raw slash-command input.
- Do not add gameplay commands or automation, including `/ma`, `/ja`, `/item`,
  `/target`, `/attack`, `/follow`, `/trade`, movement, inventory movement/use,
  buying, selling, packet injection, input simulation, timers, loops,
  game-state-triggered behavior, or detection-evasion behavior.
- One request may perform at most one addon lifecycle operation.
- Allowed lifecycle operations are only `/addon load <name>`,
  `/addon unload <name>`, and `/addon reload <name>` after strict addon-name
  validation.
- Local log output can include private chat or account-adjacent context. Treat
  it as sensitive local data and expose this MCP server only to trusted local
  clients.
- Before expanding AshitaCore behavior, check the CatsEyeXI addon policy:
  `https://catseyexi.com/addon-policy`.

Repository shape:

- `ashitadevtools/` is the Ashita addon loaded with
  `/addon load ashitadevtools`.
- `src/AshitaDevTools.Server/` is the .NET stdio MCP server.
- `install.ps1` copies the addon into the local CatsEyeXI Ashita addon folder
  and writes rollback files under `.local-backups/`.
