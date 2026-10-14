#!/usr/bin/env bash
# Testes do install.sh com um HOME temporário. Uso: ./test-install.sh
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" LANG=C; unset CLAUDE_CONFIG_DIR XDG_CONFIG_HOME LC_ALL LC_MESSAGES CLAUDE_STATUS_LANG
S="$HOME/.claude/settings.json"; B="$HOME/.local/bin/claude-status-bridge.sh"; R="$HOME/.local/bin/claude-status-summary.sh"
# Permissão em octal: GNU (Linux) ou BSD (macOS).
mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
PASS=0; FAIL=0
eq() { if [ "$2" == "$3" ]; then PASS=$((PASS+1)); echo "  ok   $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1"; echo "       esperado: [$2] obtido: [$3]"; fi; }
inst() { OUT="$("$HERE/install.sh" "$@" 2>&1)"; RC=$?; }
nbak() { find "$HOME/.claude" -name 'settings.json.bak-*' | wc -l | tr -d ' '; }

echo "== settings.json existente com hooks de terceiros"
mkdir -p "$HOME/.claude"
cat > "$S" <<'J'
{ "model": "opus", "statusLine": { "type": "command", "command": "~/old-statusline.sh" },
  "hooks": { "SessionEnd": [ { "hooks": [ { "type": "command", "command": "notify-send bye" } ] } ],
             "Stop": [ { "matcher": "", "hooks": [ { "type": "command", "command": "echo stop" } ] } ] } }
J
chmod 600 "$S"; orig="$(jq -S . "$S")"
inst
eq "exit 0" 0 "$RC"
eq "ponte copiada e executável" "true" "$([ -x "$B" ] && echo true || echo false)"
eq "resumidor copiado e executável" "true" "$([ -x "$R" ] && echo true || echo false)"
eq "1 backup criado" "1" "$(nbak)"
eq "backup = original" "$orig" "$(jq -S . "$(find "$HOME/.claude" -name 'settings.json.bak-*')")"
eq "statusLine" "{\"type\":\"command\",\"command\":\"$B\",\"padding\":0}" "$(jq -c .statusLine "$S")"
eq "PreCompact" "[\"$B --compact\"]" "$(jq -c '[.hooks.PreCompact[].hooks[].command]' "$S")"
eq "SessionEnd preserva o de terceiros" "[\"notify-send bye\",\"$B --end\"]" "$(jq -c '[.hooks.SessionEnd[].hooks[].command]' "$S")"
eq "Stop intacto" '[{"matcher":"","hooks":[{"type":"command","command":"echo stop"}]}]' "$(jq -c .hooks.Stop "$S")"
eq "outras chaves intactas" '"opus"' "$(jq -c .model "$S")"
eq "permissão preservada" "600" "$(mode "$S")"
eq "avisa sobre statusLine substituída" "true" "$(grep -q 'old-statusline' <<<"$OUT" && echo true || echo false)"

echo "== reinstalar é idempotente"
before="$(cat "$S")"; inst
eq "exit 0" 0 "$RC"
eq "settings igual" "$before" "$(cat "$S")"
eq "nenhum backup novo" "1" "$(nbak)"
eq "sem entradas duplicadas" "1" "$(jq '[.hooks[][] .hooks[] | select(.command | contains("claude-status-bridge"))] | map(select(.command | endswith("--end"))) | length' "$S")"

echo "== ponte instalada funciona"
eq "statusline" "Opus 5.5 · ctx 42% · session 31% · weekly 12%" "$(XDG_CACHE_HOME="$TMP/c" "$B" < "$HERE/bridge/fixtures/full.json")"
eq "resumidor lê o snapshot recém-gravado" "Opus 5.5 · ctx 42%" "$(XDG_CACHE_HOME="$TMP/c" "$R" | cut -d' ' -f1-5)"

echo "== --uninstall"
sleep 1; inst --uninstall
eq "exit 0" 0 "$RC"
eq "ponte removida" "false" "$([ -e "$B" ] && echo true || echo false)"
eq "resumidor removido" "false" "$([ -e "$R" ] && echo true || echo false)"
eq "2 backups" "2" "$(nbak)"
eq "statusLine removida" "null" "$(jq -c .statusLine "$S")"
eq "PreCompact removido" "null" "$(jq -c .hooks.PreCompact "$S")"
eq "SessionEnd de terceiros fica" '["notify-send bye"]' "$(jq -c '[.hooks.SessionEnd[].hooks[].command]' "$S")"
eq "Stop intacto" "echo stop" "$(jq -r '.hooks.Stop[0].hooks[0].command' "$S")"

echo "== sem settings.json"
rm -rf "$HOME/.claude"; inst
eq "exit 0" 0 "$RC"
eq "cria settings" "true" "$(jq -e '.statusLine and .hooks.PreCompact and .hooks.SessionEnd' "$S" >/dev/null && echo true || echo false)"
eq "sem backup" "0" "$(nbak)"

echo "== settings.json inválido não é tocado"
printf '{ quebrado' > "$S"; inst
eq "exit != 0" 1 "$RC"
eq "arquivo intacto" "{ quebrado" "$(cat "$S")"
eq "sem backup" "0" "$(nbak)"

echo "== alvos (--target), com comandos externos simulados"
rm -rf "$HOME"; mkdir -p "$HOME"; unset XDG_DATA_HOME
STUB="$TMP/stub"; LOG="$TMP/calls.log"; mkdir -p "$STUB"; : > "$LOG"
stub() { # stub <comando> [código de saída]
  printf '#!/usr/bin/env bash\necho "%s $*" >> "%s"\nexit %s\n' "$1" "$LOG" "${2:-0}" > "$STUB/$1"; chmod +x "$STUB/$1"
}
stub glib-compile-schemas; stub gnome-extensions
export PATH="$STUB:$PATH"
G="$HOME/.local/share/gnome-shell/extensions/claude-status@marcospaulo"

inst --target gnome
eq "gnome: exit 0" 0 "$RC"
eq "gnome: compila o schema do repo" "glib-compile-schemas $HERE/extension/schemas" "$(grep '^glib' "$LOG")"
eq "gnome: symlink para extension/" "$HERE/extension" "$(readlink "$G")"
eq "gnome: ativa" "gnome-extensions enable claude-status@marcospaulo" "$(grep enable "$LOG")"
eq "gnome: ponte também instalada" "true" "$([ -x "$B" ] && echo true || echo false)"
inst --target gnome
eq "gnome: reinstalar é idempotente" "true" "$(grep -q 'já aponta' <<<"$OUT" && [ "$RC" = 0 ] && echo true || echo false)"
rm "$G"; mkdir -p "$G"
inst --target gnome
eq "gnome: pasta de outra origem não é sobrescrita" "1" "$RC"
eq "gnome: pasta intacta" "true" "$([ -d "$G" ] && [ ! -L "$G" ] && echo true || echo false)"
rmdir "$G"; inst --target gnome
inst --uninstall --target gnome
eq "gnome: desinstala (desativa e remove o symlink)" "true" "$(grep -q disable "$LOG" && [ ! -e "$G" ] && echo true || echo false)"
eq "gnome: ponte removida junto" "false" "$([ -e "$B" ] && echo true || echo false)"

inst --target waybar
eq "waybar: módulo instalado" "true" "$([ -x "$HOME/.local/bin/claude-status-waybar.sh" ] && echo true || echo false)"
eq "waybar: indica os trechos de config" "true" "$(grep -q 'waybar/config.jsonc' <<<"$OUT" && echo true || echo false)"
inst --uninstall --target waybar
eq "waybar: módulo removido" "false" "$([ -e "$HOME/.local/bin/claude-status-waybar.sh" ] && echo true || echo false)"

P="$TMP/plugins"
inst --target macos --plugin-dir "$P"
eq "macos: plugin em --plugin-dir" "true" "$([ -x "$P/claude-status.5s.sh" ] && echo true || echo false)"
printf '#!/bin/sh\necho outro\n' > "$P/claude-status.other.sh"
mv "$P/claude-status.5s.sh" "$P/claude-status.1m.sh"
inst --uninstall --target macos --plugin-dir "$P"
eq "macos: remove o plugin mesmo renomeado, e só ele" "claude-status.other.sh" "$(ls "$P")"
printf '#!/bin/sh\necho "~/SwiftBar"\n' > "$STUB/defaults"; chmod +x "$STUB/defaults"
inst --target macos
eq "macos: pasta do SwiftBar via defaults (com ~ expandido)" "true" "$([ -x "$HOME/SwiftBar/claude-status.5s.sh" ] && echo true || echo false)"
rm "$STUB/defaults"
if [ ! -d "$HOME/Library/Application Support/xbar/plugins" ] && ! command -v defaults >/dev/null; then
  inst --target macos
  eq "macos: sem pasta conhecida falha com instrução" "true" "$([ "$RC" = 1 ] && grep -q -- '--plugin-dir' <<<"$OUT" && echo true || echo false)"
fi

: > "$LOG"; stub kpackagetool6 1
inst --target kde
eq "kde: instala quando não existe" "true" "$(grep -q -- "-i $HERE/kde/org.claudestatus.monitor" "$LOG" && echo true || echo false)"
stub kpackagetool6 0; : > "$LOG"
inst --target kde
eq "kde: atualiza quando já existe" "true" "$(grep -q -- "-u $HERE/kde/org.claudestatus.monitor" "$LOG" && echo true || echo false)"
inst --uninstall --target kde
eq "kde: remove" "true" "$(grep -q -- '-r org.claudestatus.monitor' "$LOG" && echo true || echo false)"

inst --target waybar --target kde
eq "vários alvos de uma vez" "true" "$([ "$RC" = 0 ] && [ -x "$HOME/.local/bin/claude-status-waybar.sh" ] && echo true || echo false)"
inst --target nope
eq "alvo inválido: exit 1" 1 "$RC"

echo "== config único (T12)"
rm -rf "$HOME"; mkdir -p "$HOME"
C="$HOME/.config/claude-status/config"
cval() { grep "^$1=" "$C" | cut -d= -f2; }
inst
eq "primeira instalação cria config com padrões" "70 90 15 auto" "$(cval warn) $(cval crit) $(cval inactive) $(cval lang)"
eq "config tem comentário explicando" "true" "$(grep -q '^# warn' "$C" && echo true || echo false)"
inst --warn 60 --crit 85 --lang pt
eq "flags gravam no config" "60 85 15 pt" "$(cval warn) $(cval crit) $(cval inactive) $(cval lang)"
inst --inactive 30
eq "flag nova preserva as anteriores" "60 85 30 pt" "$(cval warn) $(cval crit) $(cval inactive) $(cval lang)"
printf 'warn=55\n# meu comentário\ncrit=80\nlang=en\n' > "$C"
inst
eq "sem flags: config editado à mão fica intacto" "55 80 en" "$(cval warn) $(cval crit) $(cval lang)"
before="$(cat "$C")"; rm -f "$B"
inst --warn 95
eq "crit < warn (contando o config): exit 1" 1 "$RC"
eq "crit < warn: nada alterado (config e ponte)" "true" "$([ "$(cat "$C")" = "$before" ] && [ ! -e "$B" ] && echo true || echo false)"
inst --warn 0
eq "warn fora de 1..100: exit 1" 1 "$RC"
inst --crit abc
eq "crit não numérico: exit 1" 1 "$RC"
inst --lang xx
eq "lang inválido: exit 1" 1 "$RC"
inst --uninstall
eq "desinstalar mantém o config" "true" "$([ -f "$C" ] && grep -q 'config mantido' <<<"$OUT" && echo true || echo false)"
inst --warn 50 --crit 60
eq "resumidor instalado usa o config" "true" "$(XDG_CACHE_HOME="$TMP/c" "$R" --format json | jq -e '.level >= 0' >/dev/null && echo true || echo false)"

echo; echo "Resultado: $PASS ok, $FAIL falha(s)"; [ "$FAIL" -eq 0 ]
