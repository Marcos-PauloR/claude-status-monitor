# Claude Status Monitor

Extensão do GNOME Shell que mostra na barra superior o **consumo do plano** (janelas de 5 h e semanal) e o **tamanho do contexto** das sessões do Claude Code. Não gasta tokens: os dados vêm da própria statusline do Claude Code.

```
[ CPU ▂▄▆ ] [ MEM ▅ ] [ model · ctx · session · resets · compacts · weekly ]
                          └─ menu: cotas session/weekly, compacts da semana, uma entrada por janela com barra de ctx
```

**Status:** v1 (GNOME) concluída; v1.1 (waybar, macOS, KDE) em andamento; ver [docs/STATUS.md](docs/STATUS.md).

## Plataformas

O projeto tem duas partes: a **ponte**, que grava os snapshots a partir da statusline do Claude Code, e um **mostrador** por plataforma, que lê esses arquivos. A ponte é a mesma em todo lugar.

| Plataforma | Mostrador | Situação |
|---|---|---|
| Linux · GNOME Shell 50 | extensão (`extension/`): painel em colunas, menu e preferências | ✅ pronto |
| Linux · waybar (Sway, Hyprland…) | módulo `custom/claude` (`waybar/`): texto colorido + tooltip com cotas e janelas | ✅ pronto |
| macOS | plugin SwiftBar/xbar (`macos/`): título na barra de menus + menu com cotas e janelas | ✅ pronto (ainda não testado num Mac real) |
| Linux · KDE Plasma 6 | plasmoid nativo | 🚧 planejado (T10) |
| Qualquer terminal | a própria statusline do Claude Code (`Opus 5.5 · ctx 42% · session 31% · weekly 12%`) | ✅ pronto |

Requisitos comuns: `bash` (3.2+) e `jq` (1.6+). No Windows, a ponte roda via WSL ou Git Bash, mas ainda não há mostrador para a bandeja do sistema.

## Instalação

Requisitos (GNOME): GNOME Shell 50, `jq`, Claude Code 2.1.x.

```bash
./install.sh                      # ponte statusline + hooks em ~/.claude/settings.json (com backup)
glib-compile-schemas extension/schemas
ln -s "$PWD/extension" ~/.local/share/gnome-shell/extensions/claude-status@marcospaulo
gnome-extensions enable claude-status@marcospaulo   # no Wayland, sair e entrar na sessão
```

Desinstalar: `gnome-extensions disable claude-status@marcospaulo`, remover o symlink e `./install.sh --uninstall`.

### waybar

```bash
./install.sh                                        # ponte + resumidor em ~/.local/bin
install -m 755 waybar/claude-status-waybar.sh ~/.local/bin/
```

Depois cole `waybar/config.jsonc` na config do waybar (e `"custom/claude"` em `modules-right`) e `waybar/style.css` no `style.css`. Com `inotify-tools` instalado a barra atualiza na hora; sem ele, a cada 5 s.

### macOS (SwiftBar ou xbar)

```bash
brew install jq
brew install --cask swiftbar                        # ou: brew install --cask xbar
./install.sh                                        # ponte + resumidor em ~/.local/bin
cp macos/claude-status.5s.sh "<pasta de plugins do SwiftBar/xbar>/"
```

O `5s` do nome é o intervalo de atualização (renomeie para `10s`, `1m`… se quiser). Os dados ficam em `~/.cache/claude-status`, como no Linux.

## Desenvolvimento

- Ponte: `bridge/test.sh` · resumidor: `bridge/test-summary.sh` · instalador: `./test-install.sh` · extensão: `gjs -m extension/test.js` · waybar: `waybar/test.sh` · macOS: `macos/test.sh`
- Ao mudar o schema (`extension/schemas/*.gschema.xml`), recompilar: `glib-compile-schemas extension/schemas`
- A UI da extensão (painel, menu, preferências) é toda em inglês.

- [Especificação](docs/SPEC.md): objetivo, fonte de dados, arquitetura, contrato e requisitos
- [Plano e estimativa de tokens](docs/PLANO.md): tasks, custo estimado e riscos
