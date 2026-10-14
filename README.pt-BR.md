# Claude Status Monitor

**Português** · [English](README.md)

Mostra na barra do sistema o **consumo do seu plano do Claude Code** (a cota `session`, de 5 horas, e a `weekly`, semanal) e o **tamanho do contexto** de cada janela do Claude Code. Funciona no GNOME, KDE Plasma, waybar e macOS. Não gasta tokens: os números vêm da própria statusline do Claude Code.

```
Painel: Opus 5.5 · ctx 42% · sessão 31% · reinicia 1h12 · compactações 2 · semana 12%
Menu:   cotas da sessão e da semana, compactações na semana, uma entrada por janela aberta com a barra de ctx
```

Cores: amarelo a partir de 70%, vermelho a partir de 90% (dá para mudar). A interface aparece em português ou inglês, conforme o idioma do sistema.

## Instalar

Você precisa do Claude Code, `git`, `bash` 3.2+ e `jq` 1.6+:

| Sistema | Instalar o jq |
|---|---|
| Fedora | `sudo dnf install jq` |
| Debian / Ubuntu | `sudo apt install jq` |
| Arch | `sudo pacman -S jq` |
| macOS | `brew install jq` |

Depois baixe o projeto e rode o instalador da sua área de trabalho:

```bash
git clone https://github.com/Marcos-PauloR/claude-status-monitor.git
cd claude-status-monitor
```

| Área de trabalho | Comando | Depois de instalar |
|---|---|---|
| GNOME | `./install.sh --target gnome` | sair e entrar na sessão (o Wayland só carrega extensões novas no login) |
| KDE Plasma 6 | `./install.sh --target kde` | botão direito no painel → *Adicionar widgets* → **Claude Status Monitor** |
| waybar (Sway, Hyprland…) | `./install.sh --target waybar` | colar `waybar/config.jsonc` e `waybar/style.css` na config do waybar e recarregar |
| macOS | `brew install --cask swiftbar` e depois `./install.sh --target macos` | antes de rodar o instalador, abrir o SwiftBar uma vez e escolher uma pasta de plugins |
| Só o terminal | `./install.sh` | nada |

Por fim, **abra uma nova sessão do Claude Code**: os números aparecem depois da primeira resposta.

O instalador copia dois scripts pequenos para `~/.local/bin` e acrescenta uma `statusLine` e dois hooks no `~/.claude/settings.json`, fazendo backup desse arquivo antes. Pode rodar de novo sem problema.

## Atualizar

```bash
cd claude-status-monitor
./install.sh --update
```

Isso baixa a versão nova (`git pull`) e reinstala o que você já tinha instalado. É o único momento em que o projeto acessa a internet, e só porque você pediu. No GNOME, saia e entre na sessão depois.

> Instalou antes da v1.2? O seu `install.sh` ainda não conhece o `--update`. Rode `git pull` uma vez antes e depois `./install.sh --update`.

## Configuração

As configurações compartilhadas ficam em `~/.config/claude-status/config`. Dá para editar o arquivo à mão ou mudar pelo instalador:

```bash
./install.sh --warn 60 --crit 85 --inactive 30 --lang pt
```

| Chave | Significado | Padrão |
|---|---|---|
| `warn` | % a partir do qual o número fica amarelo | 70 |
| `crit` | % a partir do qual o número fica vermelho | 90 |
| `inactive` | minutos sem atividade até a janela sumir da lista | 15 |
| `lang` | `auto` (idioma do sistema), `en` ou `pt` | auto |

O waybar, o macOS e o terminal seguem esse arquivo. O GNOME e o KDE também têm uma tela de configuração própria:

- **GNOME:** clique no painel → *Preferências*. Escolha quais indicadores aparecem e em que ordem, dê limiares próprios a cada um e defina o idioma e a posição no painel.
- **KDE:** botão direito no widget → *Configurar Claude Status Monitor*. O que ficar como "do config" segue o arquivo acima.

## Desinstalar

Use o mesmo `--target` da instalação:

```bash
./install.sh --uninstall --target gnome    # ou: kde, waybar, macos
./install.sh --uninstall                   # se instalou só para o terminal
```

Isso remove o item do painel, os scripts e as entradas do `settings.json` (com backup). O `~/.config/claude-status/config` é mantido. Apague à mão se quiser.

## Glossário

| Termo | Significado |
|---|---|
| **ctx** | quanto do contexto da janela mais recente do Claude Code já foi usado (tokens usados ÷ tamanho do contexto). Quando enche, o Claude Code compacta a conversa |
| **sessão** (*session*) | uso da sua conta na janela atual de 5 horas, o limite que o `/usage` mostra |
| **reinicia** (*resets*) | tempo até a cota da sessão reiniciar |
| **semana** (*weekly*) | uso da sua conta na semana atual |
| **compactações** (*compacts*) | quantas vezes a conversa foi compactada (resumida para liberar contexto) |
| **modelo** (*model*) | o modelo da janela mais recente, por exemplo Opus 5.5 |
| **janela** | cada sessão aberta do Claude Code (um terminal rodando `claude`) |
| **statusline** | a linha que o Claude Code mostra abaixo do prompt; o projeto lê os números dela |
| **SwiftBar / xbar** | apps gratuitos do macOS que mostram scripts na barra de menus; a versão para macOS roda dentro de um deles |
| **plasmoid** | widget do KDE Plasma |
| **waybar** | barra de status usada com Sway, Hyprland e outros gerenciadores de janelas Wayland |

## Como funciona

```
Claude Code ──statusline/hooks──▶ ponte (bash + jq) ──▶ ~/.cache/claude-status/sessions/<id>.json
                                                                   │
                                   GNOME · KDE · waybar · macOS ◀──┘  (cada mostrador só lê os arquivos)
```

- A **ponte** (`bridge/claude-status-bridge.sh`) roda a cada mensagem do Claude Code. Grava um arquivo pequeno por sessão e continua imprimindo a statusline no terminal.
- O **resumidor** (`bridge/claude-status-summary.sh`) aplica as regras (janelas ativas, cota mais recente, cores, compactações da semana) para waybar, macOS e KDE. A extensão do GNOME tem a mesma lógica em JavaScript.
- Nada lê suas credenciais, chama modelos ou acessa a internet, exceto o `install.sh --update`.

| Plataforma | Situação |
|---|---|
| GNOME Shell 50 | ✅ em uso diário |
| KDE Plasma 6 | ✅ testado no `plasmoidviewer` |
| waybar | ✅ testado com Sway |
| macOS | ✅ pronto, ainda não testado num Mac real |
| Windows | a ponte roda no WSL ou Git Bash; ainda sem ícone na bandeja |

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

- Os scripts precisam rodar no bash 3.2 do macOS. Evite `mapfile`, arrays associativos, `case` dentro de `$( )` e opções só do GNU (`stat -c`, `date +%N`, `sed -i` sem sufixo).
- Depois de mudar o schema do GNOME (`extension/schemas/*.gschema.xml`), rode `glib-compile-schemas extension/schemas`.
- Documentos de projeto: [especificação](docs/SPEC.md), [plano](docs/PLANO.md), [status](docs/STATUS.md).
