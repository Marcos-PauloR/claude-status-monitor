#!/usr/bin/env bash
# Claude Status Monitor — resumidor dos snapshots para os mostradores sem GNOME.
#
# Uso: claude-status-summary.sh [--format json|text] [--warn N] [--crit N] [--inactive MIN]
#
# Lê ${XDG_CACHE_HOME:-~/.cache}/claude-status/{sessions/*.json,compacts.jsonl} e aplica
# as mesmas regras do painel do GNOME (extension/store.js): janelas ativas (RF05), cota do
# snapshot mais recente com limits (RF07), nível de cor (RF02) e compacts da semana (RF09).
# Opções também via ambiente: CLAUDE_STATUS_WARN, CLAUDE_STATUS_CRIT,
# CLAUDE_STATUS_INACTIVE_MINUTES. Roda com bash 3.2 (macOS) e jq 1.6+.

BASE="${XDG_CACHE_HOME:-$HOME/.cache}/claude-status"
format="text"
warn="${CLAUDE_STATUS_WARN:-70}"
crit="${CLAUDE_STATUS_CRIT:-90}"
inactive="${CLAUDE_STATUS_INACTIVE_MINUTES:-15}"

die() { printf 'claude-status-summary: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --format) format="${2:-}"; shift ;;
    --warn) warn="${2:-}"; shift ;;
    --crit) crit="${2:-}"; shift ;;
    --inactive) inactive="${2:-}"; shift ;;
    *) die "opção desconhecida: $1" ;;
  esac
  shift
done

case "$format" in json|text) ;; *) die "formato desconhecido: $format" ;; esac
for n in "$warn" "$crit" "$inactive"; do
  case "$n" in ''|*[!0-9]*) die "número inválido: $n" ;; esac
done

# Arquivos começados com '.' são temporários da escrita atômica da ponte (o glob já os ignora).
shopt -s nullglob
files=("$BASE"/sessions/*.json)
[ ${#files[@]} -eq 0 ] && files=(/dev/null)

hist="$BASE/compacts.jsonl"
[ -f "$hist" ] || hist=/dev/null

# Uma única chamada ao jq. Cada snapshot é uma linha (a ponte grava JSON compacto);
# linhas inválidas são ignoradas.
exec jq -nrR \
  --rawfile hist "$hist" \
  --arg format "$format" \
  --argjson now "${CLAUDE_STATUS_NOW:-$(date +%s)}" \
  --argjson warn "$warn" --argjson crit "$crit" --argjson inactive "$inactive" '
  def num: if type == "number" then . else null end;
  def level: if num == null then 0 elif . >= $crit then 2 elif . >= $warn then 1 else 0 end;
  def quota: if type == "object" and (.used_pct | num) != null then
      (.resets_at | num) as $r
      | if $r != null and $r <= $now then { pct: 0, resets_in: null, reset: true }
        else { pct: .used_pct, resets_in: (if $r == null then null else $r - $now end), reset: false } end
    else null end;
  # "45m", "1h12", "2d3h"; nulo/negativo vira "—".
  def dur: if . == null or . < 0 then "—" else
      (. / 60 | floor) as $m | ($m / 60 | floor) as $h
      | if $m < 60 then "\($m)m"
        elif $h < 24 then "\($h)h\($m % 60 | tostring | if length < 2 then "0" + . else . end)"
        else "\($h / 24 | floor)d\($h % 24)h" end
    end;
  def week_start($limits): ($limits.seven_day.resets_at | num) as $r
    | if $r == null then $now - 604800 elif $r <= $now then $r else $r - 604800 end;

  [ inputs | fromjson? | select(type == "object" and .schema == 1
      and (.session_id | type) == "string" and (.updated_at | type) == "number") ]
  | sort_by(-.updated_at) as $all
  | [ $all[] | select($now - .updated_at < $inactive * 60) ] as $active
  | ([ $all[] | select(.limits) ] | first // null) as $with
  | ($with.limits.five_hour | quota) as $session
  | ($with.limits.seven_day | quota) as $weekly
  | week_start($with.limits) as $since
  | ([ $hist | split("\n")[] | fromjson? | objects | .ts | num | select(. != null and . >= $since) ] | length) as $week
  | (if ($active | length) == 0 then { empty: true, level: 0, windows: [] }
     else ($active[0]) as $latest
     | ($latest.context.used_pct | num) as $ctx
     | {
         empty: false,
         model: ($latest.model // "Claude"),
         ctx: $ctx,
         compacts: ($latest.compacts | num // 0),
         session: $session,
         weekly: $weekly,
         week_compacts: $week,
         level: ([ $ctx, $session.pct, $weekly.pct ] | map(level) | max),
         windows: [ $active[] | {
           id: .session_id,
           project: (.project // null),
           name: (.session_name // null),
           model: (.model // null),
           ctx: (.context.used_pct | num),
           tokens: (.context.tokens | num),
           window: (.context.window | num),
           compacts: (.compacts | num // 0),
           level: (.context.used_pct | level)
         } ]
       } end) as $s
  | if $format == "json" then $s | tojson
    elif $s.empty then "Claude —"
    else [ $s.model,
           (if $s.ctx != null then "ctx \($s.ctx)%" else empty end),
           (if $s.session != null then "session \($s.session.pct)%", "resets \($s.session.resets_in | dur)" else empty end),
           "compacts \($s.compacts)",
           (if $s.weekly != null then "weekly \($s.weekly.pct)%" else empty end)
         ] | join(" · ")
    end
' "${files[@]}"
