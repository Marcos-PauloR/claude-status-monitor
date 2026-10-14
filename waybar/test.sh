#!/usr/bin/env bash
# Testes do módulo do waybar (sem waybar: lê a saída do script). Uso: waybar/test.sh
# Roda no modo consulta e, se houver inotifywait, também no modo inotify.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE="$HERE/claude-status-waybar.sh"
export CLAUDE_STATUS_SUMMARY="$HERE/../bridge/claude-status-summary.sh"

TMP="$(mktemp -d)"
PID=""
trap '[ -n "$PID" ] && kill $PID 2>/dev/null; rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache"
SESS="$XDG_CACHE_HOME/claude-status/sessions"

PASS=0
FAIL=0
eq() {
  if [ "$2" == "$3" ]; then PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL + 1)); printf '  FAIL %s\n       esperado: [%s] obtido: [%s]\n' "$1" "$2" "$3"; fi
}

start() { # start [args do módulo] — saída em $TMP/out
  : > "$TMP/out"
  "$MODULE" "$@" > "$TMP/out" 2>/dev/null &
  PID=$!
}
stop() { kill $PID 2>/dev/null; wait $PID 2>/dev/null; PID=""; }
last() { tail -n 1 "$TMP/out" | jq -r "$1" 2>/dev/null; }
# wait_for <filtro jq> <esperado> [segundos]: espera a última linha bater.
wait_for() {
  local i=0 max=$(( ${3:-4} * 10 ))
  while [ $i -lt $max ]; do
    [ "$(last "$1")" == "$2" ] && return 0
    sleep 0.1; i=$((i + 1))
  done
  return 1
}
write_snap() { # escrita atômica, como a ponte
  mkdir -p "$SESS"
  jq -nc --arg id "$1" --argjson t "$(date +%s)" --argjson ctx "$2" \
    '{schema: 1, session_id: $id, updated_at: $t, model: "Opus 5.5", context: {used_pct: $ctx}, limits: null}' \
    > "$SESS/.$1.tmp" && mv -f "$SESS/.$1.tmp" "$SESS/$1.json"
}

suite() { # suite <nome> <segundos de reação aceitos>
  echo "== modo $1"
  rm -rf "$XDG_CACHE_HOME"
  start
  wait_for .class empty 3; eq "começa vazio" "empty" "$(last .class)"
  eq "cria o diretório" "true" "$([ -d "$SESS" ] && echo true || echo false)"

  write_snap a 42
  wait_for .text "ctx 42%" "$2"; eq "nova janela aparece em até $2 s" "ctx 42%" "$(last .text)"
  write_snap a 95
  wait_for .class crit "$2"; eq "mudança reflete (crit)" "crit" "$(last .class)"

  rm -rf "$XDG_CACHE_HOME"
  wait_for .class empty $(( $2 + 2 )); eq "apagar o cache: volta a vazio" "empty" "$(last .class)"
  write_snap b 10
  wait_for .text "ctx 10%" $(( $2 + 2 )); eq "continua após recriar" "ctx 10%" "$(last .text)"
  eq "toda linha é JSON válido" "0" "$(jq -e . "$TMP/out" >/dev/null 2>&1; echo $?)"
  stop
}

CLAUDE_STATUS_NO_INOTIFY=1 CLAUDE_STATUS_POLL=1 suite consulta 3
if command -v inotifywait >/dev/null; then
  CLAUDE_STATUS_POLL=30 suite inotify 1
else
  echo "== modo inotify: pulado (inotifywait não instalado)"
fi

echo "== argumentos e falhas"
rm -rf "$XDG_CACHE_HOME"; write_snap a 10
CLAUDE_STATUS_NO_INOTIFY=1 CLAUDE_STATUS_POLL=1 start --warn 5 --crit 8
wait_for .class crit 3; eq "argumentos vão para o resumidor" "crit" "$(last .class)"
stop
CLAUDE_STATUS_SUMMARY=/bin/false CLAUDE_STATUS_NO_INOTIFY=1 CLAUDE_STATUS_POLL=1 start
wait_for .text "Claude ?" 3; eq "resumidor falhando: linha de fallback" "Claude ?" "$(last .text)"
stop

printf '\nResultado: %d ok, %d falha(s)\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
