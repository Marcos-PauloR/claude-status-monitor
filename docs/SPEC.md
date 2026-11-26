# Claude Status Monitor — Especificação

Extensão do GNOME Shell que mostra, na barra superior (ao lado do system-monitor-next), o **consumo do plano** e o **tamanho do contexto** das sessões do Claude Code.

## 1. Objetivo

Hoje a checagem é manual: `/usage` (89×) e `/context` (24×) no histórico. A meta é deixar esses números sempre visíveis, sem comando e **sem custo de tokens em tempo de execução**.

## 2. Ambiente alvo

| Item | Valor |
|---|---|
| SO | Linux (desenvolvido e testado no Fedora 44) |
| Desktop | GNOME Shell 50 (extensões em ESM — padrão desde o 45) |
| Claude Code | 2.1.x (testado na 2.1.284) |
| Linguagens | Bash + `jq` (ponte) · GJS/JavaScript ESM (extensão) |

## 3. Fonte de dados (oficial, sem API extra)

O Claude Code chama o comando configurado em `statusLine` passando um JSON no stdin. Ele roda no início/retomada da sessão e a cada nova mensagem do assistente, com debounce de 300 ms. Também roda no fim do `/compact` e quando a janela de rate limit atinge `resets_at`.
Doc: https://code.claude.com/docs/en/statusline

Campos usados:

| Campo | Uso |
|---|---|
| `session_id`, `session_name` | identificar a sessão |
| `workspace.project_dir` | nome do projeto (basename) |
| `model.display_name` | modelo |
| `context_window.used_percentage` | % do contexto usado |
| `context_window.context_window_size` | tamanho da janela |
| `context_window.current_usage.*` | tokens atuais (input + cache) |
| `rate_limits.five_hour.used_percentage` / `.resets_at` | cota da janela de 5 h |
| `rate_limits.seven_day.used_percentage` / `.resets_at` | cota semanal (Pro/Max) |
| `cost.total_cost_usd` | custo estimado da sessão (informativo) |

Contagem de compacts: o JSON da statusline não informa quantos compacts houve. A ponte conta isso pelo hook `PreCompact`, que recebe `session_id` e `trigger` (`manual`/`auto`).

Restrições conhecidas:
- `rate_limits` só aparece **depois da primeira resposta da API** na sessão. Antes disso, o campo não vem.
- Hooks **não** recebem dados de contexto/custo. A única fonte é a statusline.
- A cota é da conta, não da sessão. Vale sempre o snapshot mais recente entre todas as sessões.

## 4. Arquitetura

```
Claude Code ──stdin JSON──▶ bridge.sh ──escrita atômica──▶ ~/.cache/claude-status/sessions/<session_id>.json
     │                         │                                         ▲
     │                         └──stdout──▶ statusline no terminal       │ Gio.FileMonitor
     ├── hook PreCompact ──▶ bridge.sh --compact ──▶ ~/.cache/claude-status/compacts.jsonl  ▲
     └── hook SessionEnd ──▶ bridge.sh --end ──▶ remove <session_id>.json        Extensão GNOME (painel)
```

Os componentes ficam desacoplados por arquivos. A extensão não chama rede, não lê credenciais e não executa o Claude.

### 4.1 Ponte (`bridge/claude-status-bridge.sh`)
- Lê o JSON do stdin e grava um **snapshot normalizado** (seção 5) em `$XDG_CACHE_HOME/claude-status/sessions/<session_id>.json`. A escrita é atômica (`tmp` + `mv`).
- Imprime uma statusline curta no terminal: `Opus 5.5 · ctx 42% · session 31% · weekly 12% · compacts 2`. Campos ausentes são omitidos; `compacts` só aparece se for maior que 0.
- Tempo de execução abaixo de 50 ms. Usa só `jq`. Falha silenciosa: se der erro, imprime a linha mínima e **nunca** quebra a sessão.
- Hook `PreCompact` chamando `claude-status-bridge.sh --compact`: acrescenta `{ts, session_id, trigger}` em `compacts.jsonl` e descarta entradas com mais de 14 dias. O snapshot de cada sessão traz o total dela, contado a partir desse histórico.
- Hook `SessionEnd` chamando `claude-status-bridge.sh --end`: remove o snapshot da sessão. O histórico de compacts é mantido (entra na contagem semanal).
- Arquivos temporários da escrita atômica começam com `.` e devem ser ignorados pela extensão.

### 4.2 Extensão (`extension/`)
- `metadata.json`: `uuid: claude-status@marcospaulo`, `shell-version: ["50"]`.
- `extension.js`: um `PanelMenu.Button` com rótulo compacto e menu.
- Atualização via `Gio.FileMonitor` no diretório de sessões. Há um fallback por timer de 30 s, que também serve pra expirar sessões inativas.
- `prefs.js` (Adw): limiares de cor, formato do rótulo, minutos até considerar uma sessão inativa e posição no painel.

### 4.3 Outras plataformas (v1.1)

Os mostradores fora do GNOME não repetem a lógica do `store.js`: usam o **resumidor** `bridge/claude-status-summary.sh` (bash 3.2+ e jq), que aplica RF02, RF05, RF07 e RF09 sobre os mesmos arquivos e imprime em `text`, `json`, `waybar` ou `swiftbar`. Limiares e inatividade vêm de `--warn/--crit/--inactive` ou das variáveis `CLAUDE_STATUS_*`.

| Plataforma | Mostrador | Atualização |
|---|---|---|
| waybar | `waybar/claude-status-waybar.sh` (módulo contínuo, `return-type: json`) | `inotifywait` no diretório; sem ele, consulta a cada 5 s; reimprime a cada 30 s |
| macOS | `macos/claude-status.5s.sh` (SwiftBar/xbar) | intervalo do nome do arquivo (5 s) |
| KDE Plasma 6 | plasmoid `kde/org.claudestatus.monitor` (QML, motor `executable`) | intervalo configurável (5 s) |

A instalação de cada um é `./install.sh --target gnome|kde|waybar|macos`. Os alvos instalados ficam em `targets=` no config único, e `./install.sh --update` (v1.2) faz `git pull` e reinstala esses alvos. Em instalações anteriores, sem `targets=`, ele detecta o que está instalado.

## 5. Contrato do snapshot (v1)

```json
{
  "schema": 1,
  "updated_at": 1760450000,
  "session_id": "abc…",
  "session_name": "core backend",
  "project": "my-app",
  "model": "Opus 5.5",
  "context": { "used_pct": 42, "window": 200000, "tokens": 84000 },
  "compacts": 2,
  "limits": {
    "five_hour": { "used_pct": 31, "resets_at": 1760460000 },
    "seven_day": { "used_pct": 12, "resets_at": 1760900000 }
  },
  "cost_usd": 1.23
}
```
`limits` pode ser `null`, caso a sessão ainda não tenha recebido resposta da API. Dentro dele, `five_hour` ou `seven_day` podem ser `null` individualmente. Porcentagens são inteiros arredondados.

Histórico de compacts (`compacts.jsonl`, uma linha por compact, últimos 14 dias):
```json
{"ts":1760450000,"session_id":"abc…","trigger":"auto"}
```

## 5.1 Nomenclatura

A UI (painel, menu e preferências) tem inglês e português: `language` = auto (idioma da sessão), en ou pt.

| Termo na UI | Significado |
|---|---|
| `model` | modelo da janela |
| `ctx` | % do contexto da janela |
| `session` | cota da janela de 5 h da conta (mesmo nome do `/usage`: "Current session") |
| `resets` | tempo até o reset da cota `session` |
| `compacts` | compacts da janela |
| `weekly` | cota semanal da conta (`/usage`: "Current week") |
| **janela** | cada sessão aberta do Claude Code (um terminal) |

## 6. Requisitos funcionais

| ID | Requisito |
|---|---|
| RF01 | O painel segue o estilo do system-monitor-next: para cada campo, um rótulo pequeno em cima e o valor embaixo. Campos: `model`, `ctx`, `session`, `resets`, `compacts`, `weekly` (ver §5.1). `model`, `ctx` e `compacts` são da janela atualizada mais recentemente. |
| RF02 | Cada indicador do painel tem a própria cor: normal abaixo do amarelo (padrão 70%), amarelo até o vermelho (padrão 90%), vermelho a partir dele. Os limiares gerais valem para todos; `ctx`, `session` e `weekly` podem ter limiares próprios. `resets` acompanha `session`. (No waybar, macOS e KDE, o texto segue o pior indicador.) |
| RF03 | O menu (dropdown) lista cada janela ativa: projeto (e `session_name`, se houver), `model`, barra de `ctx` em % com tokens/tamanho da janela de contexto, e `compacts`. |
| RF04 | O topo do menu mostra as cotas da conta, uma vez só: `session` e `weekly`, cada uma com barra, % e "resets in 1h12" (contagem relativa). |
| RF09 | O menu mostra os compacts da semana: total de entradas em `compacts.jsonl` desde o início da janela semanal atual (`seven_day.resets_at − 7 dias`). Sem `limits`, usa os últimos 7 dias. |
| RF05 | Uma sessão é ativa se `updated_at` tiver menos de N minutos (padrão 15). As inativas somem da lista. |
| RF06 | Sem nenhum snapshot, o painel mostra `Claude —` e o menu mostra "no active windows". |
| RF07 | A cota exibida vem do snapshot mais recente que tenha `limits`. Se o `resets_at` já passou, mostra 0% / "just reset". |
| RF08 | Itens de menu "Open data folder" e "Preferences". |

## 7. Requisitos não funcionais

- **Custo de tokens em runtime: zero.** Nenhuma chamada de modelo e nenhuma API.
- Leve: no máximo 1 leitura de arquivo por evento, sem polling abaixo de 30 s e sem processos residentes além do próprio Shell.
- Seguro: não lê `~/.claude/.credentials.json` nem nenhum token, e não faz requisições de rede em runtime. A única exceção é o `install.sh --update`, que a pessoa roda por conta própria (`git pull`).
- Robusto: um JSON inválido ou parcial é ignorado com log em `journalctl`, sem derrubar a extensão.
- Passa pelos critérios de revisão do extensions.gnome.org (limpeza total em `disable()`), mesmo que não seja publicada.

## 8. Fora de escopo (v1)

- Histórico/gráfico de consumo ao longo do tempo (candidato à v2: guardar série em `history.jsonl`).
- Notificação desktop ao cruzar limiar (candidato à v2, é barato).
- Suporte a outros desktops: entregue na v1.1 (§4.3).
- Mostrador para Windows (bandeja do sistema).

## 9. Critérios de aceite

1. Ao abrir uma sessão do Claude Code e mandar 1 mensagem, o painel mostra o ctx em até 2 s.
2. Com duas sessões em projetos diferentes, ambas aparecem no menu com os valores certos.
3. Encerrar a sessão (`/exit`) faz ela sumir do menu.
4. Os valores de 5 h e 7 d batem com o `/usage` (tolerância de ±1 p.p.).
5. Desativar a extensão remove o botão e os monitores, sem erros no `journalctl -f /usr/bin/gnome-shell`.
6. Apagar o diretório de cache com a extensão ligada não gera erro (ela recria ou mostra o estado vazio).

## 10. v1.3 — contas, janela fixada e temas

Design completo: [`docs/superpowers/specs/2026-11-26-contas-fixar-temas-design.md`](superpowers/specs/2026-11-26-contas-fixar-temas-design.md). Vale para GNOME, KDE, waybar e macOS. Resumo do que o código faz:

- **Conta.** A ponte lê `CLAUDE_CONFIG_DIR` e grava `"account": "<id>"` no snapshot e em cada linha nova de `compacts.jsonl` (mudança aditiva; `schema` continua 1; sem o campo = `default`). Id: ausente, vazio ou `~/.claude` → `default`; senão o basename sem o prefixo `.claude-` (ou sem o `.` inicial), com `[^A-Za-z0-9_-]` → `_`. Uma pasta `.claude` fora da home (`/srv/x/.claude`) vira `claude`. Várias contas = instalar a ponte em cada uma (`CLAUDE_CONFIG_DIR=~/.claude-work ./install.sh`).
- **Cota e compacts por conta.** `session`, `weekly` e os compacts da semana (RF04, RF07, RF09) passam a valer por conta. Conta ativa = tem janela ativa ou cota ainda não resetada. Com uma conta só, toda saída é igual à v1.2.
- **Janela fixada.** `~/.cache/claude-status/pinned` guarda o id (saneado) da janela fixada, gravado de forma atômica. A janela em foco é a fixada, se estiver ativa; senão a mais recente (a fixação de janela que terminou ou ficou inativa é esquecida e o arquivo apagado). Resumidor: `--pin ID`, `--unpin`, `--pin-next` (alterna; depois da última, desafixa). GNOME: item no menu; KDE: botão no popup; waybar: clique esquerdo `--pin-next` e direito abre a pasta de dados; macOS: item de submenu sob a janela.
- **Config** (`~/.config/claude-status/config`), chaves novas: `theme` (padrão `default`), `panel_accounts` (`focus` | `all`, padrão `focus`) e `account.<id>=apelido`. Instalador: `--theme`, `--panel-accounts`. No GNOME as duas primeiras ficam no GSettings (`theme`, `panel-accounts`); GNOME e KDE podem sobrescrevê-las nas próprias telas.
- **Painel.** `focus`: dados da janela em foco, com o apelido da conta na frente quando há mais de uma conta ativa. `all`: `Opus 5.5 · ctx 42% · default 31%/12% · work 78%/40%`. O painel do KDE em `focus` mantém o texto da v1.2 (sem modelo e compacts).
- **Temas.** Arquivos `name`, `normal`, `warn`, `crit`, `label`, `bar`, `accent` (`chave=valor`; cores `#rgb`/`#rrggbb`; ausente, vazia ou inválida = valor da chave no tema `default`; em `normal`, `label` e `accent` esse valor é vazio = cor do texto do desktop). Embutidos em `themes/` (default, nord, dracula, catppuccin, solarized), copiados pelo instalador para `~/.local/share/claude-status/themes`; os da pessoa em `~/.config/claude-status/themes/<nome>.theme` valem mais que os embutidos de mesmo nome. Limites no KDE: com o tema `default` ficam as cores do Plasma, e o nome da conta no painel não é colorido.
- **JSON do resumidor** (`--format json`): os objetos de janela ganham `account` e `pinned`; topo ganha `pinned` (id ou `null`), `panel_accounts` (`focus` | `all`), `accounts[]` (`id`, `label`, `session`, `weekly`, `week_compacts`, `level`, `windows`), `focus` (mesmo formato de janela), `multi` (mais de uma conta listada) e `theme` (com `id`, `name` e as cores). `--list-themes` imprime `[{id,name}]`.
- **Glossário.** `account` / conta: um login do Claude Code, guardado na própria pasta de configuração.
