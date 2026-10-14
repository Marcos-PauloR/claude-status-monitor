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
git clone https://github.com/Marcos-PauloR/claude-status-monitor.git
cd claude-status-monitor
```

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
cd claude-status-monitor
./install.sh --update
```

This downloads the new version (`git pull`) and reinstalls whatever you had installed. It's the only time the project goes online, and only because you asked it to. On GNOME, log out and back in afterwards.

> Installed before v1.2? Your `install.sh` doesn't know `--update` yet. Run `git pull` once first, then `./install.sh --update`.

## Settings

Shared settings live in `~/.config/claude-status/config`. You can edit the file by hand or change it with the installer:

```bash
./install.sh --warn 60 --crit 85 --inactive 30 --lang en
```

| Setting | Meaning | Default |
|---|---|---|
| `warn` | % at which a number turns yellow | 70 |
| `crit` | % at which a number turns red | 90 |
| `inactive` | minutes without activity before a window disappears from the list | 15 |
| `lang` | `auto` (system language), `en` or `pt` | auto |

waybar, macOS and the terminal follow this file. GNOME and KDE also have their own settings screens:

- **GNOME:** click the panel → *Preferences*. Pick which indicators appear and in which order, give each one its own thresholds, and set the language and the panel position.
- **KDE:** right-click the widget → *Configure Claude Status Monitor*. Anything left as "from config" follows the file above.

## Uninstall

Use the same `--target` you installed with:

```bash
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
