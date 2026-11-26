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
export XDG_CACHE_HOME="$TMP/cache" XDG_CONFIG_HOME="$TMP/config" LANG=C
unset LC_ALL LC_MESSAGES CLAUDE_STATUS_LANG CLAUDE_STATUS_WARN CLAUDE_STATUS_CRIT CLAUDE_STATUS_INACTIVE_MINUTES
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

echo "== config.jsonc (trecho do waybar)"
# O arquivo é um trecho (chave sem chaves externas) com comentários //: embrulha e limpa.
CFG="$(grep -v '^[[:space:]]*//' "$HERE/config.jsonc" | { echo '{'; cat; echo '}'; } | jq -c '."custom/claude"' 2>/dev/null)"
eq "config é JSON válido" "object" "$(jq -r type <<<"$CFG" 2>/dev/null)"
eq "on-click alterna a fixada" "~/.local/bin/claude-status-summary.sh --pin-next" "$(jq -r '."on-click"' <<<"$CFG")"
eq "on-click-right abre a pasta" "xdg-open ~/.cache/claude-status" "$(jq -r '."on-click-right"' <<<"$CFG")"

pin_click() { # roda o on-click com o resumidor de teste (o "~/.local/bin/" vira o caminho do repositório)
  "$CLAUDE_STATUS_SUMMARY" --pin-next
}
wait_tip() { # wait_tip <regex> <segundos>: espera o tooltip da última linha casar
  local i=0 max=$(( $2 * 10 ))
  while [ $i -lt $max ]; do
    last .tooltip | grep -q "$1" && return 0
    sleep 0.1; i=$((i + 1))
  done
  return 1
}
write_acc() { # write_acc <id> <conta> <ctx>
  mkdir -p "$SESS"
  jq -nc --arg id "$1" --arg a "$2" --argjson t "$(date +%s)" --argjson ctx "$3" \
    '{schema: 1, session_id: $id, account: $a, updated_at: $t, model: "Opus 5.5", project: "my-app", context: {used_pct: $ctx}, limits: null}' \
    > "$SESS/.$1.tmp" && mv -f "$SESS/.$1.tmp" "$SESS/$1.json"
}
click_suite() { # click_suite <nome> <segundos aceitos>
  echo "== clique fixa a janela (modo $1)"
  rm -rf "$XDG_CACHE_HOME"
  write_acc w1 default 42
  write_acc w2 work 78
  start
  wait_for .class normal 3
  eq "sem fixada: nenhum 📌" "false" "$(last .tooltip | grep -q '📌' && echo true || echo false)"
  pin_click
  eq "pin-next grava pinned" "true" "$([ -f "$XDG_CACHE_HOME/claude-status/pinned" ] && echo true || echo false)"
  wait_tip '📌' "$2"; eq "📌 no tooltip em até $2 s" "true" "$(last .tooltip | grep -q '📌' && echo true || echo false)"
  eq "uma só linha de 📌" "1" "$(last .tooltip | grep -c '📌')"
  pin_click; pin_click
  wait_tip '📌' "$2"; eq "continua fixando ao alternar" "true" "$(last .tooltip | grep -q '📌' && echo true || echo false)"
  stop
}
CLAUDE_STATUS_NO_INOTIFY=1 CLAUDE_STATUS_POLL=1 click_suite consulta 3
if command -v inotifywait >/dev/null; then
  CLAUDE_STATUS_POLL=30 click_suite inotify 2
fi

printf '\nResultado: %d ok, %d falha(s)\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
