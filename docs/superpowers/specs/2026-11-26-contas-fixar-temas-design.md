# v1.3 — Contas, janela fixada e temas

Data: 2026-11-26. Complementa `docs/SPEC.md` (v1–v1.2). Vale para **todas as plataformas** (GNOME, KDE, waybar, macOS).

## 1. Motivação

1. **Contas:** quem usa mais de uma conta do Claude Code (via `CLAUDE_CONFIG_DIR`) vê as sessões misturadas e só a cota do snapshot mais recente (RF07), que pode ser de qualquer conta.
2. **Fixar janela:** com muitos terminais abertos, o painel mostra sempre a janela atualizada mais recentemente; a pessoa quer escolher qual fica no painel.
3. **Temas:** poder trocar as cores e adicionar temas próprios.

## 2. Dados

### 2.1 Conta (ponte)

- A ponte lê `CLAUDE_CONFIG_DIR` do ambiente (herdado pelo comando da statusline e pelos hooks). O JSON da statusline não traz a conta.
- Derivação do id: variável ausente, vazia ou igual a `~/.claude` → `default`. Senão, o basename sem `/` final, tirando o prefixo `.claude-` (ou só o `.` inicial, se não houver `.claude-`): `~/.claude-work` → `work`, `~/.minha-conta` → `minha-conta`. Depois aplica o mesmo saneamento do `session_id` (`[^A-Za-z0-9_-]` → `_`). Resultado vazio → `default`.
- Snapshot ganha o campo `"account": "<id>"` (mudança aditiva; `schema` continua 1). Snapshot sem `account` (gravado por versões anteriores) conta como `default`.
- `compacts.jsonl` ganha `account` em cada linha nova; linhas sem o campo contam como `default`.
- Statusline do terminal: sem mudança (a conta não aparece nela).

### 2.2 Config único (`~/.config/claude-status/config`)

Chaves novas:

| Chave | Valores | Padrão | Uso |
|---|---|---|---|
| `account.<id>` | texto | o próprio id | apelido exibido da conta (`account.work=Trabalho`) |
| `panel_accounts` | `focus` \| `all` | `focus` | o que o painel mostra (§3.2) |
| `theme` | nome do tema | `default` | tema de cores (§2.4) |

`install.sh` ganha `--theme <nome>` e `--panel-accounts focus|all`, no mesmo padrão de `--warn/--lang` (edita só a linha da chave). Apelidos são editados à mão no arquivo (documentado no README).

GNOME e KDE continuam podendo sobrescrever nas próprias preferências, com a mesma regra da v1.2: valor "do config" segue o arquivo.

### 2.3 Janela fixada

- Arquivo `~/.cache/claude-status/pinned` com um único `session_id` (uma linha). Ausente = sem fixação.
- Escrita atômica (tmp + mv), pelas UIs: GNOME, KDE, SwiftBar (via resumidor `--pin <id>` / `--unpin`) e waybar (clique alterna, via resumidor `--pin-next`).
- **Janela em foco** = a fixada, se o snapshot dela existe e está ativo (RF05); senão a atualizada mais recentemente (comportamento atual).
- Se a fixada não existe mais ou ficou inativa, quem detectar (extensão, resumidor) apaga o arquivo `pinned`: a fixação é esquecida, não volta se a sessão reaparecer.
- `--pin-next` (waybar): ordem = janelas ativas ordenadas por conta e depois por `updated_at` decrescente; avança para a próxima da lista; depois da última, desafixa (volta para "mais recente").

### 2.4 Temas

- Arquivo `<nome>.theme`, formato chave=valor (mesmo parser do config; `#` inicia comentário):

  ```
  name=Nord
  normal=#d8dee9
  warn=#ebcb8b
  crit=#bf616a
  label=#81a1c1
  bar=#5e81ac
  accent=#88c0d0
  ```

  | Chave | Uso |
  |---|---|
  | `name` | nome exibido nas preferências |
  | `normal` | valor de indicador abaixo do limiar de aviso |
  | `warn`, `crit` | valor no nível de aviso / crítico |
  | `label` | rótulos pequenos (`model`, `ctx`…) e textos secundários do menu |
  | `bar` | preenchimento das barras no nível normal (aviso/crítico usam `warn`/`crit`) |
  | `accent` | nome da conta (painel e cabeçalhos do menu) e marca da janela fixada |

- Cores aceitas: `#rgb` ou `#rrggbb`. Chave ausente, vazia ou inválida → valor do tema `default` só nessa chave (inválida gera log).
- Embutidos no repositório em `themes/`: `default`, `nord`, `dracula`, `catppuccin` (Mocha), `solarized` (Dark). Temas da pessoa em `~/.config/claude-status/themes/<nome>.theme`; com o mesmo nome, o da pessoa vence.
- `default` = as cores de hoje: `normal`/`label` vazios (cor do texto do desktop), `warn=#f6d32d`, `crit=#ff7b63`, `bar=#78aeed`, `accent` vazio (cor de texto, em negrito). No macOS, o `default` mantém os pares claro/escuro atuais; os outros temas usam a mesma cor nos dois modos.
- Tema inexistente → `default`, com log.
- `install.sh` copia os embutidos para um diretório de dados (`~/.local/share/claude-status/themes/`) que o resumidor e a extensão leem; a pasta da pessoa nunca é sobrescrita.

### 2.5 Resumidor (`bridge/claude-status-summary.sh`)

Continua sendo a fonte única para KDE, waybar e macOS. Formato `json` passa a ter:

```json
{
  "lang": "pt", "warn": 70, "crit": 90,
  "panel_accounts": "focus",
  "theme": { "name": "Nord", "normal": "#d8dee9", "warn": "#ebcb8b", "crit": "#bf616a",
             "label": "#81a1c1", "bar": "#5e81ac", "accent": "#88c0d0" },
  "pinned": "sess-123",
  "focus": { "session_id": "sess-123", "account": "work", "model": "Opus 5.5", "ctx": 42, "compacts": 2, "...": "..." },
  "accounts": [
    { "id": "default", "label": "default",
      "limits": { "five_hour": {...}, "seven_day": {...} },
      "weekly_compacts": 3, "level": 0,
      "windows": [ { "session_id": "...", "project": "...", "pinned": false, "...": "..." } ] }
  ]
}
```

- Ordem das contas: `default` primeiro, depois alfabética pelo id. Só aparecem contas com ao menos uma janela ativa **ou** cota ainda não resetada.
- RF07 e RF09 passam a valer **por conta**: cota = snapshot mais recente com `limits` daquela conta; compacts da semana = entradas do `compacts.jsonl` daquela conta.
- Campos antigos do topo (usados pela v1.2) são mantidos, agora refletindo a conta da janela em foco, para não quebrar quem não atualizou o mostrador.
- Opções novas: `--pin <id>`, `--unpin`, `--pin-next` (só alteram o `pinned` e saem).

## 3. Interface

### 3.1 Menu (todas as plataformas)

- Uma seção por conta, na ordem do §2.5. Cabeçalho: apelido da conta (cor `accent`). Abaixo, como o topo do menu de hoje: `session` e `weekly` com barra, % e "resets in", e compacts da semana.
- Em seguida, as janelas ativas daquela conta (layout atual do RF03).
- Com uma conta só, o cabeçalho com o nome é omitido (fica idêntico à v1.2).
- Cada janela tem a ação **Fixar no painel**; a fixada mostra 📌 (ícone `view-pin-symbolic` no GNOME/KDE) e a ação vira **Desafixar**. Fixar outra substitui a atual.

### 3.2 Painel

- **`focus`** (padrão): colunas de hoje (`model ctx session resets compacts weekly`), com `model`/`ctx`/`compacts` da janela em foco e `session`/`resets`/`weekly` da conta dela. Se houver mais de uma conta ativa, uma coluna extra à esquerda mostra o apelido da conta (rótulo `account`/`conta`, valor em `accent`).
- **`all`**: `model`/`ctx`/`compacts` da janela em foco + para cada conta ativa um grupo com o apelido como rótulo e `session`/`weekly` lado a lado (GNOME/KDE); no waybar/macOS, texto `Opus 5.5 · ctx 42% · default 31%/12% · work 78%/40%`.
- Liga/desliga e ordem dos indicadores (T13) continuam valendo; em `all`, `session` e `weekly` desligados somem de todos os grupos.

### 3.3 Por plataforma

| Plataforma | Contas | Fixar | Tema |
|---|---|---|---|
| GNOME | `store.js` agrupa por conta; prefs Geral ganha "Contas no painel" e "Tema" | item no menu; escreve `pinned` | cores aplicadas via `style` inline nos atores (St não recarrega CSS por arquivo); prefs listam temas embutidos + da pessoa |
| KDE | consome `accounts` do resumidor | botão no popup → `--pin`/`--unpin` | cores do `theme` do resumidor; tela de configuração ganha "Tema" e "Contas no painel" |
| waybar | texto conforme `panel_accounts`; tooltip por conta | `on-click` → `--pin-next` | `<span color>` no texto/tooltip; classes `warn`/`crit` continuam para quem usa `style.css` |
| macOS | submenus por conta | item "Fixar"/"Desafixar" (`bash=… param1=--pin …`) | cores do tema nos itens |

Textos novos (Fixar no painel, Desafixar, conta, Contas no painel, conta em foco, todas as contas, Tema) entram em `extension/i18n.js`, no `tr` do resumidor e na tradução do KDE.

## 4. Erros

| Situação | Comportamento |
|---|---|
| `CLAUDE_CONFIG_DIR` ausente / esquisito | `default` / saneado |
| `pinned` aponta para sessão inexistente ou inativa | ignora e apaga o arquivo |
| `pinned` ilegível | tratado como sem fixação |
| tema inexistente | `default` + log |
| cor inválida no tema | cor do `default` naquela chave + log |
| snapshots/compacts antigos sem `account` | `default` |

## 5. Testes

Fixtures novas (nomes genéricos, sem dados reais): duas contas (`default` e `work`), snapshot sem `account`, `pinned` órfão, `pinned` válido, tema parcial e tema com cor inválida.

| Suíte | Cobre |
|---|---|
| `bridge/test.sh` | derivação da conta (ausente, `~/.claude`, `~/.claude-work`, `~/.x/`, caracteres inseguros); `account` no snapshot e no `compacts.jsonl` |
| `bridge/test-summary.sh` | agrupamento, cota/compacts por conta, foco com e sem fixação, `pinned` órfão apagado, `--pin/--unpin/--pin-next`, temas (embutido, da pessoa sobrescrevendo, parcial, inválido), `panel_accounts` nos formatos text/waybar/swiftbar |
| `extension/test.js` | store por conta, foco/fixação, carga de tema, i18n completo |
| `kde/test.js`, `waybar/test.sh`, `macos/test.sh` | consumo dos campos novos |
| `test-install.sh` | `--theme`, `--panel-accounts`, cópia dos temas embutidos sem tocar nos da pessoa |

Validação visual: GNOME na sessão real com as duas contas abertas; KDE/waybar em container como na v1.1/v1.2.

## 6. Tasks

| Task | Conteúdo |
|---|---|
| T16 | Núcleo: conta na ponte, config novo, `pinned`, temas embutidos + parser, resumidor (`accounts`, `focus`, `--pin*`, tema), instalador |
| T17 | GNOME: store por conta, menu em seções, fixar, painel `focus`/`all`, temas, prefs |
| T18 | KDE: popup por conta, fixar, painel, tema, configuração |
| T19 | waybar + macOS |
| T20 | SPEC/README PT-EN (contas, apelidos, temas, como criar tema), versão 1.3, STATUS |

## 7. Fora de escopo

- Editor de temas com seletor de cor nas preferências.
- Temas que mudam layout, fonte ou ícone.
- Ler e-mail/dados de conta de `<config_dir>/.claude.json`.
- Lembrar a fixação depois que a sessão some.
