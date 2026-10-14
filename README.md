# Claude Status Monitor

Extensão do GNOME Shell que mostra na barra superior o **consumo do plano** (janelas de 5 h e semanal) e o **tamanho do contexto** das sessões do Claude Code. Não gasta tokens: os dados vêm da própria statusline do Claude Code.

```
[ CPU ▂▄▆ ] [ MEM ▅ ] [ model · ctx · session · resets · compacts · weekly ]
                          └─ menu: cotas session/weekly, compacts da semana, uma entrada por janela com barra de ctx
```

**Status:** T1–T5 implementadas; ver [docs/STATUS.md](docs/STATUS.md).

## Instalação

Requisitos: GNOME Shell 50, `jq`, Claude Code 2.1.x.

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
