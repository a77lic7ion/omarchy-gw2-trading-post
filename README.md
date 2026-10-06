# GW2 Trading Post

A bar widget for the [Omarchy](https://omarchy.org) Quattro shell that shows your Guild Wars 2 account wallet gold and Wizard's Vault daily objectives.

Plugin id: `shaun.gw2-trading-post`

## What it does

- Displays your GW2 wallet gold (in gold/silver/copper) as a bar icon
- Click to open a panel showing:
  - Account wallet balance
  - Wizard's Vault daily objectives with progress
  - Astral Acclaim currency icon
- Auto-refreshes every 15 minutes (configurable)
- Resyncs dailies at UTC midnight reset
- Right-click the bar icon for a notification with your wallet balance
- Middle-click to force a refresh

## Requirements

- Omarchy with the Quattro shell
- A GW2 API token (free from [account.arena.net](https://account.arena.net/applications))

## API Token Setup

The plugin reads your GW2 API token from **one of three places** (in order of priority):

1. **Plugin settings** — right-click the bar icon → Settings → enter your token
2. **Environment variable** — set `GW2_API_TOKEN` in your shell environment
3. **Token file** — write your token to `~/.config/omarchy/gw2-api-token`

No token is hardcoded in the plugin. You provide your own.

## Install

```bash
omarchy plugin add https://github.com/a77lic7ion/omarchy-gw2-trading-post.git --enable
```

## Usage

| Action | How |
| --- | --- |
| Open the panel | Click the bar icon |
| Close the panel | `Escape`, or click the icon again |
| Force refresh | Middle-click the bar icon |
| Wallet notification | Right-click the bar icon |
| From a keybind | `omarchy-shell shell summon shaun.gw2-trading-post '{}'` |

## Remove

```bash
omarchy plugin remove shaun.gw2-trading-post
```

Removal leaves no cache or config files behind.

## Notes on what it touches

- **Network**: reads `https://api.guildwars2.com/v2/account/wallet`, `https://api.guildwars2.com/v2/account/wizardsvault/daily`, and `https://api.guildwars2.com/v2/currencies/63` with your token
- **Files read**: `~/.config/omarchy/gw2-api-token` (if present)
- **Files written**: none
- **Commands run**: `curl` (read-only GET requests to the GW2 API)
- **No privileged commands, no config overwriting, no telemetry**

## License

MIT — see [LICENSE](LICENSE).