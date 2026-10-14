#!/usr/bin/env bash
# Claude Status Monitor — módulo contínuo do waybar (custom/claude, "return-type": "json").
#
# Imprime uma linha JSON a cada mudança nos snapshots da ponte. Com inotifywait
# (pacote inotify-tools) reage na hora; sem ele, consulta a cada CLAUDE_STATUS_POLL
# segundos (padrão 5). De qualquer forma reimprime a cada 30 s, para a contagem
# "resets" andar e janelas inativas sumirem.
# Argumentos extras vão para o resumidor (ex.: --warn 60 --crit 85 --inactive 30).

BASE="${XDG_CACHE_HOME:-$HOME/.cache}/claude-status"
DIR="$BASE/sessions"
TICK=30
POLL="${CLAUDE_STATUS_POLL:-5}"

SUMMARY="${CLAUDE_STATUS_SUMMARY:-}"
if [ -z "$SUMMARY" ]; then
  SUMMARY="$(command -v claude-status-summary.sh 2>/dev/null)"
  [ -n "$SUMMARY" ] || SUMMARY="$HOME/.local/bin/claude-status-summary.sh"
fi

emit() {
  "$SUMMARY" --format waybar "$@" 2>/dev/null ||
    printf '%s\n' '{"text":"Claude ?","tooltip":"claude-status-summary.sh falhou","class":"empty","alt":"empty","percentage":0}'
}

have_inotify=false
[ -z "${CLAUDE_STATUS_NO_INOTIFY:-}" ] && command -v inotifywait >/dev/null 2>&1 && have_inotify=true

while :; do
  emit "$@"
  mkdir -p "$DIR" 2>/dev/null
  if $have_inotify; then
    # 0 = evento, 2 = timeout do tick; outro código (ex.: diretório apagado) cai na consulta.
    inotifywait -qq -t "$TICK" -e close_write,moved_to,moved_from,delete,create "$DIR" "$BASE" >/dev/null 2>&1
    case $? in 0|2) ;; *) sleep "$POLL" ;; esac
    sleep 0.15 # agrupa a rajada de eventos de uma escrita atômica
  else
    sleep "$POLL"
  fi
done
