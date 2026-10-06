# GW2 Trading Post

A bar widget for the [Omarchy](https://omarchy.org) Quattro shell that shows your Guild Wars 2 account wallet gold and Wizard's Vault daily objectives.

Plugin id: `shaun.gw2-trading-post`

<img width="307" height="402" alt="image" src="https://github.com/user-attachments/assets/f9cd88ad-e9c3-4e92-9ddf-b01885219427" />

<img width="307" height="402" alt="image" src="https://github.com/user-attachments/assets/cd328c19-7881-4981-b065-9196e8b9991d" />



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
- A GW2 API token (free from [account.arena.net](https://account.arena.net/applications)) with the **Account** and **Wallet** permissions

## API token setup

Open the panel and press **Settings**, then paste your key. It is stored on this
widget's entry in `shell.json` and takes effect immediately.

The plugin reads the key from the first of these that is set:

1. **The panel's Settings view** — click the bar icon, then **Settings**
2. **Environment variable** — `GW2_API_TOKEN`
3. **Token file** — `~/.config/omarchy/gw2-api-token`

No key is hardcoded in the plugin; you supply your own.

### How the key is handled

- It is **never passed on a command line**. Anything in a process's arguments is
  readable by other local users through `/proc/<pid>/cmdline`, so `curl` is fed a
  config stream on its stdin instead (`--config -`), and the key is closed over as
  soon as it has been written. Omarchy's own network panel uses the same
  stdin-not-argv approach for the 802.1X password.
- It is stored with the rest of your shell configuration at
  `~/.config/omarchy/shell.json`, which is mode `0600` — the same file and the same
  protection Omarchy already gives your other widget settings.
- It is sent only to `api.guildwars2.com`, only over HTTPS.

## Install

```bash
omarchy plugin add https://github.com/a77lic7ion/omarchy-gw2-trading-post.git --enable
```

## Usage

| Action | How |
| --- | --- |
| Open the panel | Click the bar icon |
| Close the panel | `Escape`, or click the icon again |
| Add or change your key | Open the panel, then **Settings** |
| Force refresh | Middle-click the bar icon |
| Wallet notification | Right-click the bar icon |
| From a keybind | `omarchy-shell shell summon shaun.gw2-trading-post '{}'` |

In the Settings view: **Enter** saves, **Escape** reverts and returns to the panel,
**Clear** removes the stored key and falls back to the environment variable or file.

## Remove

```bash
omarchy plugin remove shaun.gw2-trading-post
```

Removal leaves no cache or config files behind. If you saved a key, delete its
`apiToken` entry from `~/.config/omarchy/shell.json`, or clear it from the Settings
view before removing the plugin.

## Notes on what it touches

- **Network**: reads `https://api.guildwars2.com/v2/account/wallet`,
  `https://api.guildwars2.com/v2/account/wizardsvault/daily` and
  `https://api.guildwars2.com/v2/currencies/63` with your key
- **Files read**: `~/.config/omarchy/shell.json` (your widget settings),
  `~/.config/omarchy/gw2-api-token` (if present)
- **Files written**: `~/.config/omarchy/shell.json`, only when you save or clear a
  key in the Settings view
- **Commands run**: `curl`, read-only GET requests to the GW2 API. No privileged
  commands, no other configuration is touched, no telemetry

## License

MIT — see [LICENSE](LICENSE).
