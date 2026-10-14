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
