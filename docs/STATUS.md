# Status da implementação

Atualizado em 2026-10-14.

| Task | Situação |
|---|---|
| T1 Ponte statusline | ✅ pronta — `bridge/test.sh` (60 ok) |
| T2 Instalação da ponte | ✅ instalada — `./test-install.sh` (29 ok) |
| T3 Extensão: painel | ✅ pronta e validada na sessão real (cores testadas com snapshot falso 75%/95%) |
| T4 Extensão: menu (dropdown por janela) | ✅ pronta e validada na sessão real |
| T5 Preferências | ✅ pronta e validada na sessão real |
| T6 Validação final (SPEC §9) | 🟡 automática ok; faltam 2 checagens visuais (abaixo) |

## Instalação atual da extensão

- Symlink: `~/.local/share/gnome-shell/extensions/claude-status@marcospaulo` → `extension/`
- Já incluída em `org.gnome.shell enabled-extensions`; carrega no próximo login (Wayland não recarrega o código da extensão sem sair da sessão).
- Schema compilado em `extension/schemas/gschemas.compiled` (recompilar com `glib-compile-schemas extension/schemas` se mudar).

## T6 — Validação final (2026-10-14)

### Critérios de aceite (SPEC §9)

| # | Critério | Resultado | Como |
|---|---|---|---|
| 1 | ctx aparece em até 2 s após 1 mensagem | ✅ | snapshot desta sessão com idade 1 s; ponte leva ~10 ms + debounce de 150 ms na extensão; validado no painel na T3 |
| 2 | Duas sessões em projetos diferentes aparecem no menu | 🟡 | coberto no headless (T4); **conferir no menu real** com janelas abertas em projetos diferentes |
| 3 | `/exit` remove a sessão do menu | 🟡 | hook `SessionEnd` instalado e coberto em `bridge/test.sh`; **conferir com `/exit` numa janela** |
| 4 | 5 h / 7 d batem com o `/usage` (±1 p.p.) | ✅ | validado na sessão real na T3 |
| 5 | Desativar remove botão e monitores, sem erros | ✅ | `gnome-extensions disable/enable` na sessão real → INACTIVE/ACTIVE, journal limpo; headless confirma `statusArea` vazio |
| 6 | Apagar o cache com a extensão ligada não gera erro | ✅ | `rm -rf ~/.cache/claude-status` na sessão real → diretório recriado em < 2 s, journal limpo (snapshots restaurados do backup) |

### Requisitos não funcionais (SPEC §7)

| Requisito | Resultado |
|---|---|
| Zero tokens em runtime / sem rede | ✅ nenhuma chamada de rede ou de modelo (varredura em `extension/` e `bridge/`) |
| Não lê credenciais | ✅ nenhum acesso a `~/.claude/.credentials.json` ou tokens |
| Ponte < 50 ms | ✅ mín 9 ms · mediana 10 ms · máx 11 ms (20 execuções) |
| Sem polling < 30 s, sem processos residentes | ✅ só `Gio.FileMonitor` + tick de 30 s + debounce de 150 ms |
| JSON inválido ignorado com log | ✅ `extension/test.js` |
| Limpeza total em `disable()` | ✅ timers, monitor, sinais de settings e botão; `gnome-extensions pack` gera o zip sem erro |
| Suítes | ✅ ponte 60 ok · instalador 29 ok · extensão 58 ok |

## Desfazer

```
gnome-extensions disable claude-status@marcospaulo
rm ~/.local/share/gnome-shell/extensions/claude-status@marcospaulo
./install.sh --uninstall   # remove a ponte e as entradas do settings.json
```

## Retomar a conversa

`cd claude-status-monitor && claude --continue`
