# Claude Status Monitor

Mostra na barra do sistema o **consumo do plano** (cotas `session` de 5 h e `weekly`) e o **tamanho do contexto** de cada sessão do Claude Code. Funciona no GNOME, KDE Plasma, waybar e macOS. Não gasta tokens: os dados vêm da própria statusline do Claude Code.

```
[ CPU ▂▄▆ ] [ MEM ▅ ] [ model · ctx · session · resets · compacts · weekly ]
                          └─ menu: cotas session/weekly, compacts da semana, uma entrada por janela com barra de ctx
```

## Como funciona

```
Claude Code ──statusline/hooks──▶ ponte (bash + jq) ──▶ ~/.cache/claude-status/sessions/<id>.json
                                                                   │
                                   GNOME · KDE · waybar · macOS ◀──┘  (cada mostrador só lê os arquivos)
```

- A **ponte** (`bridge/claude-status-bridge.sh`) é chamada pelo Claude Code a cada mensagem, grava um snapshot por sessão e continua imprimindo a statusline no terminal.
- O **resumidor** (`bridge/claude-status-summary.sh`) aplica as regras (janelas ativas, cota mais recente, cores, compacts da semana) para waybar, macOS e KDE. A extensão do GNOME tem a mesma lógica em JS.
- Nenhum componente acessa a rede, lê credenciais ou chama modelos.

## Plataformas

| Plataforma | Mostrador | Situação |
|---|---|---|
| Linux · GNOME Shell 50 | extensão (`extension/`): painel em colunas, menu e preferências | ✅ validado em uso real |
| Linux · KDE Plasma 6 | plasmoid nativo (`kde/`): texto no painel, popup com cotas e janelas, configurável | ✅ validado no `plasmoidviewer` |
| Linux · waybar (Sway, Hyprland…) | módulo `custom/claude` (`waybar/`): texto colorido e tooltip com cotas e janelas | ✅ validado com sway + waybar |
| macOS | plugin SwiftBar/xbar (`macos/`): título na barra de menus e menu com cotas e janelas | ✅ pronto, ainda não testado num Mac real |
| Qualquer terminal | a própria statusline do Claude Code: `Opus 5.5 · ctx 42% · session 31% · weekly 12%` | ✅ |

No Windows a ponte roda via WSL ou Git Bash, mas ainda não há mostrador para a bandeja do sistema.

## Instalação

Requisitos: Claude Code 2.1.x, `bash` 3.2+ e `jq` 1.6+ (macOS: `brew install jq`).

```bash
git clone <este repositório> && cd claude-status-monitor
./install.sh --target gnome      # ou: kde | waybar | macos (pode repetir --target)
```

O instalador sempre copia a ponte e o resumidor para `~/.local/bin` e registra `statusLine` e os hooks `PreCompact`/`SessionEnd` em `~/.claude/settings.json`, com backup antes de alterar. Rodar de novo é seguro (idempotente). Sem `--target`, instala só a ponte (statusline no terminal).

| Alvo | O que faz | Depois |
|---|---|---|
| `gnome` | compila o schema, cria o symlink em `~/.local/share/gnome-shell/extensions/` e ativa | no Wayland, sair e entrar na sessão |
| `kde` | instala ou atualiza o plasmoid com `kpackagetool6` | botão direito no painel → *Adicionar widgets* → **Claude Status Monitor** |
| `waybar` | copia `claude-status-waybar.sh` para `~/.local/bin` | colar `waybar/config.jsonc` e `waybar/style.css` na config do waybar; `inotify-tools` deixa a atualização instantânea |
| `macos` | copia o plugin para a pasta do SwiftBar ou do xbar (`--plugin-dir DIR` para escolher) | instalar antes o app: `brew install --cask swiftbar` (ou `xbar`) |

Abra uma nova sessão do Claude Code para a statusline começar a gravar os snapshots.

**Desinstalar:** `./install.sh --uninstall --target <alvo>` remove o mostrador, a ponte e as entradas do `settings.json` (com backup).

## Configuração

- **GNOME:** menu → *Preferences* (limiares de cor, inatividade, campos e posição no painel).
- **KDE:** *Configurar Claude Status Monitor* (limiares, inatividade, idioma e intervalo). O que estiver como "do config" segue `~/.config/claude-status/config`.
- **waybar e macOS:** argumentos do resumidor, `--warn 70 --crit 90 --inactive 15`, no `exec` do waybar ou em `ARGS` no plugin. Também valem as variáveis `CLAUDE_STATUS_WARN`, `CLAUDE_STATUS_CRIT` e `CLAUDE_STATUS_INACTIVE_MINUTES`.

## Desenvolvimento

| Parte | Testes |
|---|---|
| Ponte | `bridge/test.sh` |
| Resumidor | `bridge/test-summary.sh` |
| Instalador | `./test-install.sh` |
| GNOME | `gjs -m extension/test.js` |
| KDE | `gjs -m kde/test.js` |
| waybar | `waybar/test.sh` |
| macOS | `macos/test.sh` |

- Os scripts precisam rodar no bash 3.2 do macOS: evite `mapfile`, arrays associativos e opções só do GNU (`stat -c`, `date +%N`, `sed -i` sem sufixo).
- Ao mudar o schema do GNOME (`extension/schemas/*.gschema.xml`): `glib-compile-schemas extension/schemas`.
- Toda a UI dos mostradores é em inglês.

## Documentos

- [Especificação](docs/SPEC.md): objetivo, fonte de dados, arquitetura, contrato do snapshot e requisitos
- [Plano](docs/PLANO.md): tasks, estimativa de tokens e riscos
- [Status](docs/STATUS.md): andamento e resultados das validações
