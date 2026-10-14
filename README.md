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
| Linux · waybar (Sway, Hyprland…) | módulo `custom/claude` | 🚧 planejado (T8) |
| macOS | plugin SwiftBar/xbar | 🚧 planejado (T9) |
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

## Desenvolvimento

- Ponte: `bridge/test.sh` · instalador: `./test-install.sh` · extensão: `gjs -m extension/test.js`
- Ao mudar o schema (`extension/schemas/*.gschema.xml`), recompilar: `glib-compile-schemas extension/schemas`
- A UI da extensão (painel, menu, preferências) é toda em inglês.

- [Especificação](docs/SPEC.md): objetivo, fonte de dados, arquitetura, contrato e requisitos
- [Plano e estimativa de tokens](docs/PLANO.md): tasks, custo estimado e riscos
