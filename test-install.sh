#!/usr/bin/env bash
# Testes do install.sh com um HOME temporário. Uso: ./test-install.sh
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; unset CLAUDE_CONFIG_DIR
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

echo; echo "Resultado: $PASS ok, $FAIL falha(s)"; [ "$FAIL" -eq 0 ]
