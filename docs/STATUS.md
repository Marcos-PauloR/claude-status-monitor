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
| **v1.1** | |
| T7 Resumidor + portabilidade (macOS) | ✅ pronta — `bridge/test-summary.sh` (31 ok); ponte 62 ok e instalador 32 ok também no **bash 3.2** (imagem `bash:3.2`, mesma versão do macOS) |
| T8 waybar | ✅ pronta — `waybar/test.sh` (9 ok; 16 com inotify), resumidor 46 ok; validada com sway 1.11 + waybar 0.15 headless em container (barra, cores e atualização ao vivo; tooltip não renderizado no headless) |
| T9 macOS (SwiftBar/xbar) | ✅ pronta — `macos/test.sh` (10 ok, simulando o PATH mínimo do SwiftBar), resumidor 63 ok; todas as suítes ok no bash 3.2; **falta validar num Mac real** |
| T10 KDE Plasma 6 (plasmoid) | ✅ pronta — `gjs -m kde/test.js` (19 ok); carregado no `plasmoidviewer` do Plasma 6.7.5 (container, sway headless): painel e popup ok, sem erros de QML; **tela de configuração não exercitada** |
| T11 Docs e instalação por plataforma | ✅ pronta — `install.sh --target gnome\|kde\|waybar\|macos` (instalador 54 ok, com comandos externos simulados; `--target gnome` rodado de verdade aqui, idempotente); README reescrito; SPEC §4.3 |
| **v1.2** | |
| T12 Config único + idiomas (núcleo) | ✅ pronta — `~/.config/claude-status/config` (warn/crit/inactive/lang) lido pela ponte e pelo resumidor; `install.sh --warn --crit --inactive --lang`; ponte 67, resumidor 84, instalador 66 ok (também no bash 3.2) |
| T13 GNOME: preferências em abas + idioma + limiares por indicador | ✅ pronta — abas General/Indicators/About (arrastar para reordenar, liga/desliga, limiares próprios para ctx/session/weekly), PT/EN, cor por coluna; extensão 71 ok, instalador 69 ok; prefs renderizadas em container (EN e PT, 8 prints) e painel/menu no GNOME headless; **validada pelo usuário na sessão real** |
| T14 KDE: idioma + config | ✅ pronta — plasmoid segue o config único (limiares, inatividade, idioma) e a tela de configuração sobrescreve ("do config" = 0/vazio; quem ajustou na v1.1 mantém o valor, pois o KConfig só grava o que mudou); resumidor JSON traz `lang`/`warn`/`crit`; versão 1.2 em todos os mostradores (GNOME: `version-name` no About); KDE 37 ok, resumidor 90 ok, demais suítes ok; plasmoidviewer em container: painel e popup em PT com cores dos limiares do config, tela de configuração renderizada (padrão e com valores próprios), sem erros de QML; **falta validar num KDE real** |
| T15 `--update` + README PT/EN | ⏳ próxima |

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
./install.sh --uninstall --target gnome   # desativa e remove a extensão, a ponte e as entradas do settings.json
```

## Retomar a conversa

`cd claude-status-monitor && claude --continue`
