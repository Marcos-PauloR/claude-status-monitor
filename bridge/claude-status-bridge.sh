#!/usr/bin/env bash
# Claude Status Monitor — ponte statusline.
#
# Uso (configurado em ~/.claude/settings.json):
#   statusLine:      claude-status-bridge.sh             JSON da statusline no stdin
#   hook PreCompact: claude-status-bridge.sh --compact   JSON do hook no stdin
#   hook SessionEnd: claude-status-bridge.sh --end       JSON do hook no stdin
#
# Grava um snapshot normalizado (contrato v1, docs/SPEC.md §5) em
# ${XDG_CACHE_HOME:-~/.cache}/claude-status/sessions/<session_id>.json
# e imprime uma statusline curta. Nunca falha: qualquer erro vira a linha mínima.
# Idioma da statusline: CLAUDE_STATUS_LANG > lang= em ~/.config/claude-status/config >
# idioma do sistema (pt_* -> português, resto inglês).

exec 2>/dev/null

BASE="${XDG_CACHE_HOME:-$HOME/.cache}/claude-status"
DIR="$BASE/sessions"
HIST="$BASE/compacts.jsonl"
HIST_DAYS=14
FALLBACK="Claude"

input="$(cat)"

lang="${CLAUDE_STATUS_LANG:-}"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/claude-status/config"
if [ -z "$lang" ] && [ -f "$CONFIG" ]; then
  while IFS='=' read -r key value || [ -n "$key" ]; do
    key="${key//[[:space:]]/}"
    [ "$key" = "lang" ] && lang="${value//[[:space:]]/}"
  done < "$CONFIG"
fi
case "$lang" in
  en|pt) ;;
  *) case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in pt*) lang="pt" ;; *) lang="en" ;; esac ;;
esac

# Só caracteres seguros no nome do arquivo (evita path traversal).
safe_id() { printf '%s' "${1//[^A-Za-z0-9_-]/_}"; }

# write_atomic <destino> <conteúdo>
write_atomic() {
  local tmp
  tmp="$(mktemp "$(dirname "$1")/.$(basename "$1").XXXXXX")" &&
    printf '%s\n' "$2" > "$tmp" &&
    mv -f "$tmp" "$1" ||
    { rm -f "$tmp"; return 1; }
}

case "${1:-}" in
  --end)
    id="$(jq -r '.session_id // empty' <<<"$input")"
    [ -n "$id" ] && rm -f "$DIR/$(safe_id "$id").json"
    exit 0
    ;;
  --compact)
    # Registra o compact no histórico e descarta entradas com mais de HIST_DAYS dias.
    old=""
    [ -f "$HIST" ] && old="$(cat "$HIST")"
    new="$(jq -nrc --arg old "$old" --argjson days "$HIST_DAYS" --argjson ev "$input" '
      (now | floor) as $now
      | ($old | split("\n")[] | select(length > 0) | fromjson? | objects | select(.ts >= $now - $days * 86400)),
        ($ev | select(.session_id) | { ts: $now, session_id, trigger: (.trigger // null) })
      | tojson
    ')" || exit 0
    mkdir -p "$BASE" && write_atomic "$HIST" "$new"
    exit 0
    ;;
esac

hist_file="$HIST"
[ -f "$hist_file" ] || hist_file=/dev/null

# Uma única chamada ao jq: linha 1 = session_id, linha 2 = statusline, linha 3 = snapshot.
out="$(jq -r --rawfile hist "$hist_file" --arg lang "$lang" '
  def pct: if type == "number" then round else null end;
  def tr: if $lang == "pt" then ({ session: "sessão", weekly: "semana", compacts: "compactações" }[.] // .) else . end;
  def window($w): if ($w | type) == "object"
    then { used_pct: ($w.used_percentage | pct), resets_at: $w.resets_at }
    else null end;

  (.context_window // {}) as $cw
  | ($cw.current_usage) as $u
  | (.rate_limits // null) as $rl
  | .session_id as $sid
  | {
      schema: 1,
      updated_at: (now | floor),
      session_id: $sid,
      session_name: .session_name,
      project: ((.workspace.project_dir // .workspace.current_dir // .cwd // "")
                | rtrimstr("/") | split("/") | last | select(. != "") // null),
      model: .model.display_name,
      context: {
        used_pct: ($cw.used_percentage | pct),
        window: $cw.context_window_size,
        tokens: (if ($u | type) == "object"
                 then ($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0)
                      + ($u.cache_read_input_tokens // 0)
                 else null end)
      },
      compacts: ([ $hist | split("\n")[] | select(length > 0) | fromjson? | objects
                   | select(.session_id == $sid) ] | length),
      limits: (if ($rl | type) == "object" and ($rl.five_hour or $rl.seven_day)
               then { five_hour: window($rl.five_hour), seven_day: window($rl.seven_day) }
               else null end),
      cost_usd: .cost.total_cost_usd
    } as $s
  | ($s.session_id // ""),
    ([ ($s.model // "Claude"),
       (if $s.context.used_pct != null then "ctx \($s.context.used_pct)%" else empty end),
       (if $s.limits.five_hour != null then "\("session" | tr) \($s.limits.five_hour.used_pct)%" else empty end),
       (if $s.limits.seven_day != null then "\("weekly" | tr) \($s.limits.seven_day.used_pct)%" else empty end),
       (if $s.compacts > 0 then "\("compacts" | tr) \($s.compacts)" else empty end)
     ] | join(" · ")),
    ($s | tojson)
' <<<"$input")"

if [ $? -ne 0 ] || [ -z "$out" ]; then
  printf '%s\n' "$FALLBACK"
  exit 0
fi

{ IFS= read -r id; IFS= read -r line; IFS= read -r snapshot; } <<<"$out"

printf '%s\n' "${line:-$FALLBACK}"

if [ -n "$id" ] && mkdir -p "$DIR"; then
  write_atomic "$DIR/$(safe_id "$id").json" "$snapshot"
fi

exit 0
