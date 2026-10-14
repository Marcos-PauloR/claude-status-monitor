# Plano de implementação

Cada task fecha em si (dá pra parar entre elas). As estimativas de tokens são para implementar com o Claude Code, contando leitura, escrita, testes e uma rodada de ajustes. São ordens de grandeza, não um orçamento exato.

| # | Task | Entregável | Esforço | Tokens (est.) |
|---|---|---|---|---|
| T1 | Ponte statusline | `bridge/claude-status-bridge.sh` (statusline, `--compact`, `--end`) + testes com JSON de exemplo (`bridge/fixtures/*.json`, `bridge/test.sh`) | baixo | 40–80k |
| T2 | Instalação da ponte | `install.sh`: copia a ponte para `~/.local/bin`, faz merge de `statusLine` e dos hooks `PreCompact` e `SessionEnd` em `~/.claude/settings.json` com backup | baixo | 30–60k |
| T3 | Extensão: esqueleto + rótulo | `metadata.json`, `extension.js` com FileMonitor, leitura de snapshots e RF01/RF02/RF06 (painel em colunas: rótulo pequeno + valor) | médio | 100–180k |
| T4 | Extensão: menu | RF03, RF04, RF05, RF07, RF08, RF09 | médio | 80–150k |
| T5 | Preferências | `prefs.js` + `schemas/*.gschema.xml` (limiares, inatividade, formato) | baixo/médio | 60–100k |
| T6 | Validação | roteiro dos critérios de aceite (SPEC §9) executado numa sessão aninhada do GNOME (`dbus-run-session gnome-shell --devkit` no GNOME 49+) | baixo | 40–80k |


### v1.1 — outras plataformas

A ponte já grava os snapshots em arquivos (contrato v1). Cada plataforma só precisa de um mostrador. Para não repetir a lógica do `store.js` três vezes, um **resumidor comum** em bash + jq calcula o que mostrar, e os mostradores só formatam.

| # | Task | Entregável |
|---|---|---|
| T7 | Resumidor + portabilidade | `bridge/claude-status-summary.sh` (`--format json\|text`, mesmas regras de RF02/RF05/RF07/RF09); ponte, instalador e testes rodando com bash 3.2 e ferramentas BSD (macOS) |
| T8 | waybar | `--format waybar` + módulo `custom/claude` (exemplo de config e CSS) com atualização por sinal |
| T9 | macOS | `--format swiftbar` + plugin SwiftBar/xbar (barra + menu) |
| T10 | KDE Plasma 6 | plasmoid nativo (QML) lendo `--format json`: texto no painel + popup com cotas e janelas |
| T11 | Docs e instalação | `install.sh --target gnome\|waybar\|macos\|kde`, README por plataforma, validação |

### v1.2 — idiomas e configuração única

Pedido após o feedback do primeiro usuário externo: instalação mais simples, interface em português e inglês, e limiares de cor definidos por quem instala.

| # | Task | Entregável |
|---|---|---|
| T12 | Config único + idiomas no núcleo | `~/.config/claude-status/config` (`warn`, `crit`, `inactive`, `lang=auto\|en\|pt`) lido pela ponte e pelo resumidor; `install.sh --warn --crit --inactive --lang` |
| T13 | GNOME | preferências em abas (General, Indicators, About) no estilo do system-monitor-next: arrastar para reordenar, liga/desliga e limiares próprios por indicador; `language` (auto/en/pt); cor por coluna; instalador aplica as flags no GSettings |
| T14 | KDE | idioma e limiares do config único (a tela de configuração pode sobrescrever) |
| T15 | README PT/EN | link real, comandos prontos por plataforma, desinstalação explícita, glossário |

**Total estimado: ~350k a 650k tokens.** Usar Sonnet nas tasks T1, T2 e T5 tende a reduzir o custo. Opus faz mais sentido em T3/T4 (API do Shell, ciclo de vida da extensão).

**MVP mais barato:** T1 + T2 + T3 (~170–320k). Esse conjunto já entrega o número no painel e a statusline no terminal. Menu e preferências podem vir depois.

## Riscos

| Risco | Mitigação |
|---|---|
| Campos da statusline mudarem entre versões do Claude Code | A ponte normaliza para o contrato v1 (`schema: 1`), e a extensão só conhece o contrato |
| `rate_limits` ausente até a 1ª resposta | RF07: usa o snapshot mais recente com `limits` |
| API do GNOME Shell mudar na próxima versão | Isolar o acesso ao painel em um módulo pequeno e atualizar `shell-version` |
| Statusline já usada pra outra coisa | A ponte também imprime a linha do terminal, então substitui sem perda |

## Estrutura do repositório

```
claude-status-monitor/
├── README.md
├── docs/
│   ├── SPEC.md
│   └── PLANO.md
├── bridge/
│   ├── claude-status-bridge.sh
│   ├── fixtures/
│   └── test.sh
├── extension/
│   ├── metadata.json
│   ├── extension.js
│   ├── prefs.js
│   ├── stylesheet.css
│   └── schemas/org.gnome.shell.extensions.claude-status.gschema.xml
└── install.sh
```
