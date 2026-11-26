# Claude Status Monitor

[Português](README.pt-BR.md) · **English**

Shows your **Claude Code plan usage** (the 5-hour `session` and the `weekly` quota) and the **context size** of each Claude Code window in your desktop's top bar. Works on GNOME, KDE Plasma, waybar and macOS. It costs no tokens: the numbers come from Claude Code's own statusline.

```
Panel:  Opus 5.5 · ctx 42% · session 31% · resets 1h12 · compacts 2 · weekly 12%
Menu:   session and weekly quotas, compacts this week, one entry per open window with its ctx bar
```

Colors: yellow from 70%, red from 90% (configurable). The UI is in English or Portuguese, following your system language.

## Install

You need Claude Code, `git`, `bash` 3.2+ and `jq` 1.6+:

| System | Install jq |
|---|---|
| Fedora | `sudo dnf install jq` |
| Debian / Ubuntu | `sudo apt install jq` |
| Arch | `sudo pacman -S jq` |
| macOS | `brew install jq` |

Then download the project and run the installer for your desktop:

```bash
git clone https://github.com/Marcos-PauloR/claude-status-monitor.git ~/.local/share/claude-status-monitor
cd ~/.local/share/claude-status-monitor
```

Keep this folder: the GNOME extension runs from it, and updates are pulled into it.

| Desktop | Command | After installing |
|---|---|---|
| GNOME | `./install.sh --target gnome` | log out and back in (Wayland only loads new extensions on login) |
| KDE Plasma 6 | `./install.sh --target kde` | right-click the panel → *Add Widgets* → **Claude Status Monitor** |
| waybar (Sway, Hyprland…) | `./install.sh --target waybar` | paste `waybar/config.jsonc` and `waybar/style.css` into your waybar config and reload it |
| macOS | `brew install --cask swiftbar` then `./install.sh --target macos` | open SwiftBar once and choose a plugin folder before running the installer |
| Terminal only | `./install.sh` | nothing |

Finally, **open a new Claude Code session**: the numbers show up after its first reply.

The installer copies two small scripts to `~/.local/bin` and adds a `statusLine` and two hooks to `~/.claude/settings.json`, saving a backup of that file first. Running it again is safe.

## Update

```bash
cd ~/.local/share/claude-status-monitor && ./install.sh --update
```

This downloads the new version (`git pull`) and reinstalls whatever you had installed. It's the only time the project goes online, and only because you asked it to. On GNOME, log out and back in afterwards.

> Cloned somewhere else? Use that folder instead. The installer prints the exact update command at the end of every install.
>
> Installed before v1.2? Your `install.sh` doesn't know `--update` yet. Run `git pull` in that folder once, then `./install.sh --update`.

## Settings

Shared settings live in `~/.config/claude-status/config`. You can edit the file by hand or change it with the installer:

```bash
./install.sh --warn 60 --crit 85 --inactive 30 --lang en --theme nord
```

| Setting | Meaning | Default |
|---|---|---|
| `warn` | % at which a number turns yellow | 70 |
| `crit` | % at which a number turns red | 90 |
| `inactive` | minutes without activity before a window disappears from the list | 15 |
| `lang` | `auto` (system language), `en` or `pt` | auto |
| `theme` | color theme (see [Themes](#themes)) | default |
| `panel_accounts` | `focus` or `all` (see [Multiple accounts](#multiple-accounts)) | focus |
| `account.<id>` | nickname of an account | the id |

waybar, macOS and the terminal follow this file. GNOME and KDE also have their own settings screens:

- **GNOME:** click the panel → *Preferences*. Pick which indicators appear and in which order, give each one its own thresholds, and set the language and the panel position.
- **KDE:** right-click the widget → *Configure Claude Status Monitor*. Anything left as "from config" follows the file above.

## Multiple accounts

Claude Code keeps one account per config folder, chosen with the `CLAUDE_CONFIG_DIR` environment variable (`~/.claude` by default). The monitor tells accounts apart by that folder, so each account gets its own `session` and `weekly` quota and its own windows.

Install the bridge into each account's settings by running the installer once per account:

```bash
./install.sh                                       # the default account (~/.claude)
CLAUDE_CONFIG_DIR=~/.claude-work ./install.sh      # another account
```

The account id comes from the folder name: unset, empty or `~/.claude` is `default`; otherwise the folder name without the `.claude-` prefix (or without the leading `.`), with unsafe characters turned into `_`. So `~/.claude-work` is `work`. A `.claude` folder outside your home, such as `/srv/x/.claude`, becomes the account `claude`.

Give an account a nickname in `~/.config/claude-status/config`:

```
account.work=Personal
```

With more than one active account, the menu shows one section per account. The panel shows what `panel_accounts` says (also `--panel-accounts` on the installer): `focus` (default) shows the account of the window in focus, with its nickname in front; `all` shows every account's quotas, like `default 31%/12% · work 78%/40%`. GNOME and KDE can override this in their own settings. With a single account nothing changes: no account names appear anywhere.

## Pinning a window

By default the panel follows the most recently updated window. To keep a specific window in the panel instead, pin it:

| Platform | How |
|---|---|
| GNOME | menu → the window's *Pin to panel* item |
| KDE | the pin button on the window in the popup |
| waybar | left click cycles through the windows (after the last one it unpins); right click opens the data folder |
| macOS | the *Pin to panel* item in the submenu under the window |

A pinned window shows 📌. The pin is forgotten when that window ends or goes inactive, and the panel goes back to the most recent window. From a terminal: `claude-status-summary.sh --pin <session_id>`, `--unpin` or `--pin-next`.

## Themes

A theme sets the colors of the panel text and the bars. Built-in themes: `default`, `nord`, `dracula`, `catppuccin` and `solarized`. Pick one with the installer, in the config (`theme=nord`), or in the GNOME and KDE settings screens:

```bash
./install.sh --theme nord
```

To make your own, copy a built-in one (they are in `themes/`) to `~/.config/claude-status/themes/my-theme.theme` and edit it. Then use `--theme my-theme`. A theme of yours with the same name as a built-in one wins over it.

```
name=My theme
normal=#d8dee9
warn=#ebcb8b
crit=#bf616a
label=#81a1c1
bar=#5e81ac
accent=#88c0d0
```

| Key | Colors |
|---|---|
| `name` | name shown in the settings screens |
| `normal` | numbers below the yellow threshold |
| `warn` | numbers from the yellow threshold |
| `crit` | numbers from the red threshold |
| `label` | the small labels (`ctx`, `session`…) |
| `bar` | the progress bars |
| `accent` | account names and headings |

Colors are `#rgb` or `#rrggbb`. An empty key uses your desktop's text color; an invalid one falls back to the `default` theme's color.

Limits:

- On KDE, the `default` theme keeps the colors of your Plasma theme (a `default.theme` of your own is not applied there), and the account name in the panel is not colored.
- Dark themes such as `nord` and `dracula` have low contrast on a light desktop theme.
- The KDE panel text in `focus` mode keeps the v1.2 style (no model or compacts).

## Uninstall

Use the same `--target` you installed with:

```bash
cd ~/.local/share/claude-status-monitor
./install.sh --uninstall --target gnome    # or: kde, waybar, macos
./install.sh --uninstall                   # terminal-only install
```

This removes the panel item, the scripts and the `settings.json` entries (with a backup). Your `~/.config/claude-status/config` is kept. Delete it by hand if you want.

## Glossary

| Term | Meaning |
|---|---|
| **ctx** | how full the context of the most recent Claude Code window is (tokens used ÷ context size). When it fills up, Claude Code compacts the conversation |
| **session** | your account's usage in the current 5-hour window, the limit `/usage` shows |
| **resets** | time until the session quota resets |
| **weekly** | your account's usage in the current week |
| **compacts** | how many times the conversation was compacted (summarized to free up context) |
| **model** | the model of the most recent window, e.g. Opus 5.5 |
| **window** | each open Claude Code session (one terminal running `claude`) |
| **account** | one Claude Code login, kept in its own config folder (`CLAUDE_CONFIG_DIR`); each has its own `session` and `weekly` quota |
| **statusline** | the line Claude Code shows below the prompt; this project uses it to read the numbers |
| **SwiftBar / xbar** | free macOS apps that show scripts in the menu bar; the macOS version runs inside one of them |
| **plasmoid** | a KDE Plasma widget |
| **waybar** | a status bar used with Sway, Hyprland and other Wayland window managers |

## How it works

```
Claude Code ──statusline/hooks──▶ bridge (bash + jq) ──▶ ~/.cache/claude-status/sessions/<id>.json
                                                                   │
                                   GNOME · KDE · waybar · macOS ◀──┘  (each one only reads these files)
```

- The **bridge** (`bridge/claude-status-bridge.sh`) runs on every Claude Code message. It saves one small file per session and still prints the statusline in the terminal.
- The **summarizer** (`bridge/claude-status-summary.sh`) applies the rules (active windows, latest quota, colors, compacts this week) for waybar, macOS and KDE. The GNOME extension has the same logic in JavaScript.
- Nothing reads your credentials, calls a model or goes online, except `install.sh --update`.

| Platform | Status |
|---|---|
| GNOME Shell 50 | ✅ used daily |
| KDE Plasma 6 | ✅ tested in `plasmoidviewer` |
| waybar | ✅ tested with Sway |
| macOS | ✅ ready, not yet tested on a real Mac |
| Windows | the bridge runs under WSL or Git Bash; no tray icon yet |

## Development

| Part | Tests |
|---|---|
| Bridge | `bridge/test.sh` |
| Summarizer | `bridge/test-summary.sh` |
| Installer | `./test-install.sh` |
| GNOME | `gjs -m extension/test.js` |
| KDE | `gjs -m kde/test.js` |
| waybar | `waybar/test.sh` |
| macOS | `macos/test.sh` |

- Scripts must run on macOS's bash 3.2. Avoid `mapfile`, associative arrays, `case` inside `$( )`, and GNU-only options (`stat -c`, `date +%N`, `sed -i` without a suffix).
- After changing the GNOME schema (`extension/schemas/*.gschema.xml`), run `glib-compile-schemas extension/schemas`.
- Design docs (in Portuguese): [spec](docs/SPEC.md), [plan](docs/PLANO.md), [status](docs/STATUS.md).
