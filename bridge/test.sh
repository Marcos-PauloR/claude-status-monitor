#!/usr/bin/env bash
# Testes da ponte statusline. Uso: bridge/test.sh
# Não toca no cache real: XDG_CACHE_HOME aponta para um diretório temporário.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE="$HERE/claude-status-bridge.sh"
FX="$HERE/fixtures"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache"
SESS="$XDG_CACHE_HOME/claude-status/sessions"

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }

eq() { # eq <descrição> <esperado> <obtido>
  if [ "$2" == "$3" ]; then ok "$1"; else fail "$1" "esperado: [$2] obtido: [$3]"; fi
}

run() { # run <fixture> [args...] -> define OUT e RC
  local fx="$1"; shift
  OUT="$("$BRIDGE" "$@" < "$FX/$fx" 2>"$TMP/stderr")"
  RC=$?
}

snap() { # snap <session_id> <filtro jq>
  jq -c "$2" "$SESS/$1.json" 2>/dev/null
}

echo "== full.json (sessão completa)"
before=$(date +%s)
run full.json
after=$(date +%s)
eq "exit 0" 0 "$RC"
eq "statusline" "Opus 5.5 · ctx 42% · session 31% · weekly 12%" "$OUT"
eq "snapshot existe" "true" "$([ -f "$SESS/sess-full-001.json" ] && echo true || echo false)"
eq "schema" "1" "$(snap sess-full-001 .schema)"
eq "session_id" '"sess-full-001"' "$(snap sess-full-001 .session_id)"
eq "session_name" '"core backend"' "$(snap sess-full-001 .session_name)"
eq "project = basename(project_dir)" '"my-app"' "$(snap sess-full-001 .project)"
eq "model" '"Opus 5.5"' "$(snap sess-full-001 .model)"
eq "context" '{"used_pct":42,"window":200000,"tokens":84000}' "$(snap sess-full-001 .context)"
eq "limits" '{"five_hour":{"used_pct":31,"resets_at":1760460000},"seven_day":{"used_pct":12,"resets_at":1760900000}}' "$(snap sess-full-001 .limits)"
eq "cost_usd" "1.2345" "$(snap sess-full-001 .cost_usd)"
ua=$(snap sess-full-001 .updated_at)
eq "updated_at = agora" "true" "$([ "$ua" -ge "$before" ] && [ "$ua" -le "$after" ] && echo true || echo false)"
eq "sem arquivos temporários sobrando" "1" "$(find "$SESS" -type f | wc -l | tr -d ' ')"
eq "compacts" "0" "$(snap sess-full-001 .compacts)"

echo "== no-limits.json (antes da 1ª resposta com rate_limits)"
run no-limits.json
eq "exit 0" 0 "$RC"
eq "statusline sem session/weekly" "Sonnet 5.5 · ctx 8%" "$OUT"
eq "limits null" "null" "$(snap sess-nolimits-002 .limits)"
eq "session_name null" "null" "$(snap sess-nolimits-002 .session_name)"
eq "project" '"proj"' "$(snap sess-nolimits-002 .project)"
eq "tokens = input + cache" "16000" "$(snap sess-nolimits-002 .context.tokens)"
eq "cost 0" "0" "$(snap sess-nolimits-002 .cost_usd)"

echo "== fresh-session.json (current_usage/used_percentage null)"
run fresh-session.json
eq "exit 0" 0 "$RC"
eq "statusline sem ctx" "Opus 5.5" "$OUT"
eq "context nulo" '{"used_pct":null,"window":1000000,"tokens":null}' "$(snap sess-fresh-003 .context)"
eq "cost null" "null" "$(snap sess-fresh-003 .cost_usd)"

echo "== partial-limits.json (só five_hour, project_dir com barra final)"
run partial-limits.json
eq "statusline" "Opus 5.5 · ctx 91% · session 100%" "$OUT"
eq "seven_day null" '{"five_hour":{"used_pct":100,"resets_at":1760460000},"seven_day":null}' "$(snap sess-partial-004 .limits)"
eq "project sem barra final" '"my-app"' "$(snap sess-partial-004 .project)"

echo "== unsafe-id.json (session_id com path traversal)"
run unsafe-id.json
eq "exit 0" 0 "$RC"
eq "nada fora do diretório de sessões" "false" "$([ -e "$TMP/cache/etc/evil.json" ] || [ -e "$TMP/etc/evil.json" ] && echo true || echo false)"
eq "arquivo com id saneado" "true" "$([ -f "$SESS/______etc_evil.json" ] && echo true || echo false)"
eq "session_id original preservado no conteúdo" '"../../etc/evil"' "$(snap ______etc_evil .session_id)"

echo "== invalid.json (JSON quebrado)"
count_before=$(find "$SESS" -type f | wc -l | tr -d ' ')
run invalid.json
eq "exit 0" 0 "$RC"
eq "linha mínima" "Claude" "$OUT"
eq "nenhum snapshot novo" "$count_before" "$(find "$SESS" -type f | wc -l | tr -d ' ')"
eq "stderr vazio" "" "$(cat "$TMP/stderr")"

echo "== no-session-id.json"
run no-session-id.json
eq "exit 0" 0 "$RC"
eq "statusline ainda sai" "Opus 5.5 · ctx 5%" "$OUT"
eq "nenhum snapshot novo" "$count_before" "$(find "$SESS" -type f | wc -l | tr -d ' ')"

echo "== stdin vazio"
OUT="$("$BRIDGE" < /dev/null 2>"$TMP/stderr")"; RC=$?
eq "exit 0" 0 "$RC"
eq "linha mínima" "Claude" "$OUT"

echo "== cache em diretório sem permissão de escrita"
RO="$TMP/ro"; mkdir -p "$RO"; chmod 500 "$RO"
OUT="$(XDG_CACHE_HOME="$RO" "$BRIDGE" < "$FX/full.json" 2>"$TMP/stderr")"; RC=$?
chmod 700 "$RO"
eq "exit 0" 0 "$RC"
eq "statusline ainda sai" "Opus 5.5 · ctx 42% · session 31% · weekly 12%" "$OUT"
eq "stderr vazio" "" "$(cat "$TMP/stderr")"

echo "== --compact (hook PreCompact)"
HIST="$XDG_CACHE_HOME/claude-status/compacts.jsonl"
eq "compacts = 0 antes de qualquer compact" "0" "$(snap sess-full-001 .compacts)"
mkdir -p "$(dirname "$HIST")"
printf '%s\n' '{"ts":1,"session_id":"sess-full-001","trigger":"auto"}' 'lixo' > "$HIST"
run pre-compact.json --compact
eq "exit 0" 0 "$RC"
eq "sem saída" "" "$OUT"
run pre-compact.json --compact
eq "entrada antiga e linha inválida descartadas" "2" "$(wc -l < "$HIST" | tr -d ' ')"
eq "registro" '{"session_id":"sess-full-001","trigger":"auto"}' "$(head -1 "$HIST" | jq -c '{session_id, trigger}')"
run full.json
eq "snapshot conta 2 compacts" "2" "$(snap sess-full-001 .compacts)"
eq "statusline mostra compacts" "Opus 5.5 · ctx 42% · session 31% · weekly 12% · compacts 2" "$OUT"
run no-limits.json
eq "outra sessão continua com 0" "0" "$(snap sess-nolimits-002 .compacts)"
run invalid.json --compact
eq "--compact com JSON inválido: exit 0" 0 "$RC"
eq "histórico intacto" "2" "$(wc -l < "$HIST" | tr -d ' ')"
printf '5\n' >> "$HIST"
run full.json
eq "linha que não é objeto no histórico não derruba a statusline" "Opus 5.5 · ctx 42% · session 31% · weekly 12% · compacts 2" "$OUT"
run pre-compact.json --compact
eq "--compact descarta a linha que não é objeto" "3" "$(wc -l < "$HIST" | tr -d ' ')"

echo "== --end (hook SessionEnd)"
run session-end.json --end
eq "exit 0" 0 "$RC"
eq "sem saída" "" "$OUT"
eq "snapshot removido" "false" "$([ -e "$SESS/sess-full-001.json" ] && echo true || echo false)"
eq "outras sessões intactas" "true" "$([ -f "$SESS/sess-nolimits-002.json" ] && echo true || echo false)"
run invalid.json --end
eq "--end com JSON inválido: exit 0" 0 "$RC"

echo "== desempenho (< 50 ms por chamada, média de 20)"
# date +%N não existe no macOS (BSD); lá o perl dá os milissegundos.
now_ms() {
  local n; n="$(date +%s%N)"
  case "$n" in *N) perl -MTime::HiRes=time -e 'printf "%d\n", time() * 1000' ;; *) echo $((n / 1000000)) ;; esac
}
start=$(now_ms)
for _ in $(seq 20); do "$BRIDGE" < "$FX/full.json" > /dev/null; done
avg_ms=$(( ($(now_ms) - start) / 20 ))
eq "média ${avg_ms} ms < 50 ms" "true" "$([ "$avg_ms" -lt 50 ] && echo true || echo false)"

echo
echo "Resultado: $PASS ok, $FAIL falha(s)"
[ "$FAIL" -eq 0 ]
