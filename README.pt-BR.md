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
git clone https://github.com/Marcos-PauloR/claude-status-monitor.git ~/.local/share/claude-status-monitor
cd ~/.local/share/claude-status-monitor
```

Não apague essa pasta: a extensão do GNOME roda a partir dela, e as atualizações chegam nela.

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
cd ~/.local/share/claude-status-monitor && ./install.sh --update
```

Isso baixa a versão nova (`git pull`) e reinstala o que você já tinha instalado. É o único momento em que o projeto acessa a internet, e só porque você pediu. No GNOME, saia e entre na sessão depois.

> Clonou em outro lugar? Use essa pasta no lugar. O instalador mostra o comando exato de atualizar no fim de toda instalação.
>
> Instalou antes da v1.2? O seu `install.sh` ainda não conhece o `--update`. Rode `git pull` nessa pasta uma vez e depois `./install.sh --update`.

## Configuração

As configurações compartilhadas ficam em `~/.config/claude-status/config`. Dá para editar o arquivo à mão ou mudar pelo instalador:

```bash
./install.sh --warn 60 --crit 85 --inactive 30 --lang pt --theme nord
```

| Chave | Significado | Padrão |
|---|---|---|
| `warn` | % a partir do qual o número fica amarelo | 70 |
| `crit` | % a partir do qual o número fica vermelho | 90 |
| `inactive` | minutos sem atividade até a janela sumir da lista | 15 |
| `lang` | `auto` (idioma do sistema), `en` ou `pt` | auto |
| `theme` | tema de cores (veja [Temas](#temas)) | default |
| `panel_accounts` | `focus` ou `all` (veja [Várias contas](#várias-contas)) | focus |
| `account.<id>` | apelido de uma conta | o id |

O waybar, o macOS e o terminal seguem esse arquivo. O GNOME e o KDE também têm uma tela de configuração própria:

- **GNOME:** clique no painel → *Preferências*. Escolha quais indicadores aparecem e em que ordem, dê limiares próprios a cada um e defina o idioma e a posição no painel.
- **KDE:** botão direito no widget → *Configurar Claude Status Monitor*. O que ficar como "do config" segue o arquivo acima.

## Várias contas

O Claude Code guarda uma conta por pasta de configuração, escolhida pela variável de ambiente `CLAUDE_CONFIG_DIR` (`~/.claude` por padrão). O monitor separa as contas por essa pasta: cada conta tem a própria cota de `session` e de `weekly` e as próprias janelas.

Instale a ponte nas configurações de cada conta rodando o instalador uma vez por conta:

```bash
./install.sh                                       # a conta padrão (~/.claude)
CLAUDE_CONFIG_DIR=~/.claude-work ./install.sh      # outra conta
```

O id da conta vem do nome da pasta: variável ausente, vazia ou `~/.claude` é `default`; senão, o nome da pasta sem o prefixo `.claude-` (ou sem o `.` inicial), com caracteres inseguros trocados por `_`. Assim, `~/.claude-work` vira `work`. Uma pasta `.claude` fora da sua home, como `/srv/x/.claude`, vira a conta `claude`.

Dê um apelido à conta em `~/.config/claude-status/config`:

```
account.work=Trabalho
```

Com mais de uma conta ativa, o menu mostra uma seção por conta. O painel segue o `panel_accounts` (também `--panel-accounts` no instalador): `focus` (padrão) mostra a conta da janela em foco, com o apelido na frente; `all` mostra as cotas de todas as contas, como `default 31%/12% · work 78%/40%`. O GNOME e o KDE podem sobrescrever isso nas próprias configurações. Com uma conta só, nada muda: nenhum nome de conta aparece.

## Fixar uma janela

Por padrão o painel segue a janela atualizada mais recentemente. Para manter uma janela específica no painel, fixe-a:

| Plataforma | Como |
|---|---|
| GNOME | menu → item *Fixar no painel* da janela |
| KDE | botão de fixar na janela, no popup |
| waybar | clique esquerdo alterna entre as janelas (depois da última, desafixa); botão direito abre a pasta de dados |
| macOS | item *Fixar no painel* no submenu sob a janela |

A janela fixada mostra 📌. A fixação é esquecida quando a janela termina ou fica inativa, e o painel volta para a janela mais recente. No terminal: `claude-status-summary.sh --pin <session_id>`, `--unpin` ou `--pin-next`.

## Temas

Um tema define as cores do texto do painel e das barras. Temas embutidos: `default`, `nord`, `dracula`, `catppuccin` e `solarized`. Escolha um pelo instalador, no config (`theme=nord`) ou nas telas de configuração do GNOME e do KDE:

```bash
./install.sh --theme nord
```

Para criar o seu, copie um embutido (estão em `themes/`) para `~/.config/claude-status/themes/meu-tema.theme` e edite. Depois use `--theme meu-tema`. Um tema seu com o mesmo nome de um embutido vale mais que ele.

```
name=Meu tema
normal=#d8dee9
warn=#ebcb8b
crit=#bf616a
label=#81a1c1
bar=#5e81ac
accent=#88c0d0
```

| Chave | Cores |
|---|---|
| `name` | nome mostrado nas telas de configuração |
| `normal` | números abaixo do limiar amarelo |
| `warn` | números a partir do limiar amarelo |
| `crit` | números a partir do limiar vermelho |
| `label` | os rótulos pequenos (`ctx`, `sessão`…) |
| `bar` | as barras de progresso |
| `accent` | nomes de conta e títulos |

As cores são `#rgb` ou `#rrggbb`. Chave ausente, vazia ou inválida usa o valor dessa chave no tema `default`; em `normal`, `label` e `accent` esse valor é vazio, ou seja, a cor do texto do desktop.

Limites:

- No KDE, o tema `default` mantém as cores do seu tema do Plasma (um `default.theme` seu não é aplicado lá), e o nome da conta no painel não é colorido.
- Temas escuros, como `nord` e `dracula`, têm pouco contraste num tema claro do desktop.
- O texto do painel do KDE no modo `focus` mantém o estilo da v1.2 (sem modelo nem compactações).

## Desinstalar

Use o mesmo `--target` da instalação:

```bash
cd ~/.local/share/claude-status-monitor
./install.sh --uninstall --target gnome    # ou: kde, waybar, macos
./install.sh --uninstall                   # se instalou só para o terminal
```

O `--uninstall` limpa só o `settings.json` da conta atual (`${CLAUDE_CONFIG_DIR:-~/.claude}`), mas remove a ponte compartilhada em `~/.local/bin`. Se você configurou contas extras, desinstale cada uma também (antes ou junto com a principal), senão elas continuariam chamando um script apagado:

```bash
CLAUDE_CONFIG_DIR=~/.claude-work ./install.sh --uninstall
```

Do mesmo modo, o `--update` refaz o merge só nas configurações da conta atual; as outras contas continuam funcionando porque o caminho da ponte é o mesmo.

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
| **conta** (*account*) | um login do Claude Code, guardado na própria pasta de configuração (`CLAUDE_CONFIG_DIR`); cada uma tem a própria cota de `session` e `weekly` |
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
- Para gerar o zip do GNOME, `gnome-extensions pack` sozinho deixa de fora os módulos extras; use `cd extension && gnome-extensions pack --force --extra-source=config.js --extra-source=i18n.js --extra-source=store.js --extra-source=themes.js --extra-source=watcher.js --extra-source=icons .`. O zip tem só a extensão: a ponte e os temas embutidos continuam vindo do `install.sh`.
- Documentos de projeto: [especificação](docs/SPEC.md), [plano](docs/PLANO.md), [status](docs/STATUS.md).
