#!/usr/bin/env bash
# Claude Status Monitor — resumidor dos snapshots para os mostradores sem GNOME.
#
# Uso: claude-status-summary.sh [--format text|json|waybar|swiftbar] [--warn N] [--crit N]
#                               [--inactive MIN] [--lang auto|en|pt] [--theme NOME]
#                               [--panel-accounts focus|all]
#      claude-status-summary.sh --pin SESSION_ID | --unpin | --pin-next   (janela fixada)
#      claude-status-summary.sh --list-themes                             (JSON [{id,name}])
#
# Lê ${XDG_CACHE_HOME:-~/.cache}/claude-status/{sessions/*.json,compacts.jsonl,pinned} e aplica
# as mesmas regras do painel do GNOME (extension/store.js): janelas ativas (RF05), cota e
# compacts da semana por conta (RF07, RF09), janela em foco = fixada ou mais recente, nível de
# cor (RF02). Precedência: flag > ambiente (CLAUDE_STATUS_WARN, _CRIT, _INACTIVE_MINUTES, _LANG) >
# ${XDG_CONFIG_HOME:-~/.config}/claude-status/config (warn=, crit=, inactive=, lang=, theme=,
# panel_accounts=, account.<id>=apelido) > padrão.
# Temas: <config>/claude-status/themes > ${XDG_DATA_HOME:-~/.local/share}/claude-status/themes >
# themes/ do repositório. Roda com bash 3.2 (macOS) e jq 1.6+.

BASE="${XDG_CACHE_HOME:-$HOME/.cache}/claude-status"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-status"
CONFIG="$CONFIG_DIR/config"
DATA_THEMES="${XDG_DATA_HOME:-$HOME/.local/share}/claude-status/themes"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$HERE/$(basename "${BASH_SOURCE[0]}")"
PINNED="$BASE/pinned"

die() { printf 'claude-status-summary: %s\n' "$1" >&2; exit 2; }
log() { printf 'claude-status-summary: %s\n' "$1" >&2; }
trim() { local v="$1"; v="${v#"${v%%[![:space:]]*}"}"; printf '%s' "${v%"${v##*[![:space:]]}"}"; }
is_num() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; }
safe_id() { printf '%s' "${1//[^A-Za-z0-9_-]/_}"; }
H='[0-9a-fA-F]'
is_color() { case "$1" in "#"$H$H$H|"#"$H$H$H$H$H$H) return 0 ;; esac; return 1; }
write_atomic() {
  local tmp
  mkdir -p "$(dirname "$1")" &&
    tmp="$(mktemp "$(dirname "$1")/.$(basename "$1").XXXXXX")" &&
    printf '%s\n' "$2" > "$tmp" &&
    mv -f "$tmp" "$1" ||
    { rm -f "$tmp"; return 1; }
}

# Config: uma chave=valor por linha, '#' comenta; valores inválidos são ignorados.
cfg_warn="" cfg_crit="" cfg_inactive="" cfg_lang="" cfg_theme="" cfg_panel="" labels=""
if [ -f "$CONFIG" ]; then
  while IFS='=' read -r key value || [ -n "$key" ]; do
    key="$(trim "$key")"; value="$(trim "${value:-}")"
    case "$key" in
      warn) is_num "$value" && cfg_warn="$value" ;;
      crit) is_num "$value" && cfg_crit="$value" ;;
      inactive) is_num "$value" && cfg_inactive="$value" ;;
      lang) case "$value" in auto|en|pt) cfg_lang="$value" ;; esac ;;
      theme) cfg_theme="$value" ;;
      panel_accounts) case "$value" in focus|all) cfg_panel="$value" ;; esac ;;
      account.*)
        id="$(safe_id "${key#account.}")"
        if [ -n "$id" ] && [ -n "$value" ]; then labels="$labels$id=$value"$'\n'; fi ;;
    esac
  done < "$CONFIG"
fi

format="text" action="" pin_arg="" opt_theme="" opt_panel=""
warn="${CLAUDE_STATUS_WARN:-${cfg_warn:-70}}"
crit="${CLAUDE_STATUS_CRIT:-${cfg_crit:-90}}"
inactive="${CLAUDE_STATUS_INACTIVE_MINUTES:-${cfg_inactive:-15}}"
lang="${CLAUDE_STATUS_LANG:-${cfg_lang:-auto}}"

while [ $# -gt 0 ]; do
  case "$1" in
    --format) format="${2:-}"; shift ;;
    --warn) warn="${2:-}"; shift ;;
    --crit) crit="${2:-}"; shift ;;
    --inactive) inactive="${2:-}"; shift ;;
    --lang)
      case "${2:-}" in auto|en|pt) lang="$2" ;; *) die "idioma inválido: ${2:-} (auto, en ou pt)" ;; esac
      shift ;;
    --theme) opt_theme="${2:-}"; [ -n "$opt_theme" ] || die "--theme precisa de um nome"; shift ;;
    --panel-accounts)
      case "${2:-}" in focus|all) opt_panel="$2" ;; *) die "--panel-accounts inválido: ${2:-} (focus ou all)" ;; esac
      shift ;;
    --pin) case "${2:-}" in ""|-*) die "--pin precisa de um session_id" ;; esac
           action="pin"; pin_arg="$(safe_id "${2:-}")"; [ -n "$pin_arg" ] || die "--pin precisa de um session_id"; shift ;;
    --unpin) action="unpin" ;;
    --pin-next) action="pin-next" ;;
    --list-themes) action="list-themes" ;;
    *) die "opção desconhecida: $1" ;;
  esac
  shift
done

case "$format" in json|text|waybar|swiftbar) ;; *) die "formato desconhecido: $format" ;; esac
for n in "$warn" "$crit" "$inactive"; do
  is_num "$n" || die "número inválido: $n"
done
case "$lang" in
  en|pt) ;;
  *) case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in pt*) lang="pt" ;; *) lang="en" ;; esac ;;
esac
panel="${opt_panel:-${cfg_panel:-focus}}"
now="${CLAUDE_STATUS_NOW:-$(date +%s)}"

shopt -s nullglob

case "$action" in
  pin) write_atomic "$PINNED" "$pin_arg"; exit 0 ;;
  unpin) rm -f "$PINNED"; exit 0 ;;
  list-themes)
    seen=" " rows=""
    for f in "$CONFIG_DIR"/themes/*.theme "$DATA_THEMES"/*.theme "$HERE"/../themes/*.theme; do
      id="$(basename "$f" .theme)"
      case "$id" in ''|*[!A-Za-z0-9_-]*) continue ;; esac
      case "$seen" in *" $id "*) continue ;; esac
      seen="$seen$id "
      name="$(sed -n 's/^[[:space:]]*name[[:space:]]*=//p' "$f" | tail -n 1)"
      name="$(trim "$name")"
      rows="$rows$id	${name:-$id}"$'\n'
    done
    case "$seen" in *" default "*) ;; *) rows="${rows}default	Default"$'\n' ;; esac
    printf '%s' "$rows" | jq -Rnc '[inputs | split("\t") | {id: .[0], name: .[1]}]
      | sort_by([(if .id == "default" then 0 else 1 end), .id])'
    exit 0 ;;
esac

# Tema: começa no default embutido; o arquivo só troca as chaves válidas.
theme="${opt_theme:-${cfg_theme:-default}}"
t_name="Default" t_normal="" t_warn="#f6d32d" t_crit="#ff7b63" t_label="" t_bar="#78aeed" t_accent=""
load_theme() {
  local name="$1" file="" f key value
  case "$name" in ''|*[!A-Za-z0-9_-]*) log "tema inválido: $name (usando default)"; theme="default"; return ;; esac
  for f in "$CONFIG_DIR/themes/$name.theme" "$DATA_THEMES/$name.theme" "$HERE/../themes/$name.theme"; do
    if [ -f "$f" ]; then file="$f"; break; fi
  done
  if [ -z "$file" ]; then
    [ "$name" = "default" ] || log "tema não encontrado: $name (usando default)"
    theme="default"; return
  fi
  [ "$name" = "default" ] || t_name="$name"
  while IFS='=' read -r key value || [ -n "$key" ]; do
    key="$(trim "$key")"; value="$(trim "${value:-}")"
    case "$key" in
      name) [ -n "$value" ] && t_name="$value" ;;
      normal|warn|crit|label|bar|accent)
        [ -n "$value" ] || continue
        if is_color "$value"; then eval "t_$key=\$value"
        else log "tema $name: cor inválida em $key ($value)"; fi ;;
    esac
  done < "$file"
}
load_theme "$theme"

# Fixação: vale só se a sessão existe e está ativa; senão o arquivo é apagado (spec §2.3).
pinned=""
if [ -f "$PINNED" ]; then
  IFS= read -r pinned < "$PINNED" || true
  pinned="$(safe_id "$pinned")"
  if [ -n "$pinned" ]; then
    t=""
    [ -f "$BASE/sessions/$pinned.json" ] &&
      t="$(jq -r 'select(.schema == 1) | .updated_at | numbers | floor' "$BASE/sessions/$pinned.json" 2>/dev/null)"
    if ! is_num "$t" || [ $((now - t)) -ge $((inactive * 60)) ]; then rm -f "$PINNED"; pinned=""; fi
  fi
fi

files=("$BASE"/sessions/*.json)
[ ${#files[@]} -eq 0 ] && files=(/dev/null)
hist="$BASE/compacts.jsonl"
[ -f "$hist" ] || hist=/dev/null

[ "$action" = "pin-next" ] && format="pin-next"

# Uma única chamada ao jq. Cada snapshot é uma linha (a ponte grava JSON compacto);
# linhas inválidas são ignoradas.
out="$(jq -nrR \
  --rawfile hist "$hist" \
  --arg format "$format" --arg lang "$lang" --arg base "$BASE" --arg self "$SELF" \
  --arg swiftbar "${SWIFTBAR:-}" --arg panel "$panel" --arg pinned "$pinned" --arg labels "$labels" \
  --arg theme_id "$theme" --arg t_name "$t_name" --arg t_normal "$t_normal" --arg t_warn "$t_warn" \
  --arg t_crit "$t_crit" --arg t_label "$t_label" --arg t_bar "$t_bar" --arg t_accent "$t_accent" \
  --argjson now "$now" \
  --argjson warn "$warn" --argjson crit "$crit" --argjson inactive "$inactive" '
  def num: if type == "number" then . else null end;
  def tr: if $lang == "pt" then ({
      "session": "sessão", "weekly": "semana", "resets": "reinicia", "compacts": "compactações",
      "resets in": "reinicia em", "just reset": "reiniciada", "no data yet": "sem dados ainda",
      "compacts this week": "compactações na semana", "no active windows": "nenhuma janela ativa",
      "(no project)": "(sem projeto)", "Open data folder": "Abrir pasta de dados", "Refresh": "Atualizar",
      "Pin to panel": "Fixar no painel", "Unpin": "Desafixar"
    }[.] // .) else . end;
  def sid: gsub("[^A-Za-z0-9_-]"; "_");
  def acc: (.account // "default") | if type == "string" and length > 0 then sid else "default" end;
  def is_pinned: $pinned != "" and ((.session_id | sid) == $pinned);
  def level: if num == null then 0 elif . >= $crit then 2 elif . >= $warn then 1 else 0 end;
  def quota: if type == "object" and (.used_pct | num) != null then
      (.resets_at | num) as $r
      | if $r != null and $r <= $now then { pct: 0, resets_in: null, reset: true }
        else { pct: .used_pct, resets_in: (if $r == null then null else $r - $now end), reset: false } end
    else null end;
  def dur: if . == null or . < 0 then "—" else
      (. / 60 | floor) as $m | ($m / 60 | floor) as $h
      | if $m < 60 then "\($m)m"
        elif $h < 24 then "\($h)h\($m % 60 | tostring | if length < 2 then "0" + . else . end)"
        else "\($h / 24 | floor)d\($h % 24)h" end
    end;
  def when: if .reset then ("just reset" | tr) else "\("resets in" | tr) \(.resets_in | dur)" end;
  def tokens: if num == null then "—"
      elif . >= 1000000 then "\(. / 100000 | round / 10)M"
      elif . >= 1000 then "\(. / 1000 | round)k"
      else tostring end;
  def esc: tostring | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
  { id: $theme_id, name: $t_name, normal: $t_normal, warn: $t_warn, crit: $t_crit,
    label: $t_label, bar: $t_bar, accent: $t_accent } as $theme
  # Pango: só pinta quando o tema define a cor (vazio = cor do texto).
  | def paint($c): if $c == "" then . else "<span color=\"\($c)\">\(.)</span>" end;
  def color: [$theme.bar, $theme.warn, $theme.crit][level];
  def blocks: ((. // 0) | if . < 0 then 0 elif . > 100 then 100 else . end) as $p
    | ($p / 10 | floor) as $full | (if $p / 10 - $full >= 0.5 then 1 else 0 end) as $half
    | [ "\("█" * $full // "")\(if $half == 1 then "▌" else "" end)", "░" * (10 - $full - $half) // "" ];
  def bar: blocks as $b | "<span color=\"\(. // 0 | color)\">\($b[0])</span>\($b[1])";
  def sbesc: tostring | gsub("\\|"; "¦") | sub("^-"; "‐");
  # SwiftBar/xbar: o tema default mantém os pares clara/escura; os outros usam a mesma cor.
  def sbcolor: level as $l
    | (if $theme_id == "default" then "" else [$theme.normal, $theme.warn, $theme.crit][$l] end) as $c
    | if $c != "" then " color=\($c)"
      else [(if $swiftbar != "" then ["#1d1d1f", "#f5f5f7"] else null end),
            ["#b8860b", "#f6d32d"], ["#d63c25", "#ff7b63"]][$l]
        | if . == null then "" elif $swiftbar != "" then " color=\(.[0]),\(.[1])" else " color=\(.[0])" end
      end;
  def sbplain: 0 | sbcolor | if . == "" then "" else " |" + . end;
  def sbaccent: if $theme.accent != "" then " color=\($theme.accent)" else (0 | sbcolor) end;
  def sbquota($title): ($title | tr) as $name | ($name + "         " | .[0:9]) as $t
    | if . == null then "\($name)  \("no data yet" | tr)\(sbplain)"
      else "\($t)\(.pct | blocks | add)  \(.pct)%  \(when) | font=Menlo size=12\(.pct | sbcolor)" end;
  def pct: if . == null then "—" else "\(.)%" end;
  def key($k): "<b>\($k | tr | paint($theme.label))</b>";
  def quota_line($title): if . == null then "\(key($title))  \("no data yet" | tr)"
      else "\(key($title))  <tt>\(.pct | bar)</tt>  \(.pct)%  \(when)" end;
  def week_start($limits): ($limits.seven_day.resets_at | num) as $r
    | if $r == null then $now - 604800 elif $r <= $now then $r else $r - 604800 end;
  def win: {
      id: .session_id, account: acc,
      project: (.project // null), name: (.session_name // null), model: (.model // null),
      ctx: (.context.used_pct | num), tokens: (.context.tokens | num), window: (.context.window | num),
      compacts: (.compacts | num // 0), level: (.context.used_pct | level), pinned: is_pinned
    };
  def sbtitle: (if .pinned then "📌 " else "" end)
    + ([.project // ("(no project)" | tr), .name] | map(select(. != null) | sbesc) | join(" — "));
  def title: (if .pinned then "📌 " else "" end)
    + ([.project // ("(no project)" | tr), .name] | map(select(. != null)) | join(" — "));

  ($labels | split("\n") | map(select(length > 0) | capture("^(?<key>[^=]+)=(?<value>.*)$"))
   | from_entries) as $names
  | [ inputs | fromjson? | select(type == "object" and .schema == 1
      and (.session_id | type) == "string" and (.updated_at | type) == "number") ]
  | sort_by(-.updated_at) as $all
  | [ $all[] | select($now - .updated_at < $inactive * 60) ] as $active
  | [ $hist | split("\n")[] | fromjson? | objects | select((.ts | num) != null) ] as $events
  | ($active | map(win)) as $windows
  | ([ $active[] | select(is_pinned) ] | first // $active[0] // null) as $fsnap
  | [ $all[] | acc ] | unique | sort_by([(if . == "default" then 0 else 1 end), .])
  | [ .[] as $id
      | ([ $all[] | select(acc == $id and .limits) ] | first // null) as $with
      | ($with.limits.five_hour | quota) as $session
      | ($with.limits.seven_day | quota) as $weekly
      | week_start($with.limits) as $since
      | { id: $id, label: ($names[$id] // $id), session: $session, weekly: $weekly,
          week_compacts: ([ $events[] | select(acc == $id and .ts >= $since) ] | length),
          level: ([ $session.pct, $weekly.pct ] | map(level) | max),
          windows: [ $windows[] | select(.account == $id) ] }
      | select((.windows | length) > 0 or (.session // {}).reset == false or (.weekly // {}).reset == false) ]
  | . as $accounts
  | (if $fsnap == null then { empty: true, level: 0, windows: [], focus: null }
     else ($fsnap | win) as $focus
     | ([ $accounts[] | select(.id == $focus.account) ] | first) as $A
     | {
         empty: false,
         model: ($fsnap.model // "Claude"),
         ctx: $focus.ctx,
         compacts: $focus.compacts,
         session: $A.session,
         weekly: $A.weekly,
         week_compacts: $A.week_compacts,
         level: ([ $focus.ctx, $A.session.pct, $A.weekly.pct ] | map(level) | max),
         windows: $windows,
         focus: $focus
       } end)
  | . + { accounts: $accounts, multi: (($accounts | length) > 1),
          pinned: (if $pinned == "" then null else $pinned end),
          panel_accounts: $panel, theme: $theme }
  | . as $s
  | ($s.focus.account // "default") as $fa
  | [ if $s.multi and $panel == "focus" then ($names[$fa] // $fa) else empty end ] as $prefix
  | ([ $s.model, (if $s.ctx != null then "ctx \($s.ctx)%" else empty end) ]
     + [ $s.accounts[] | "\(.label) \(.session.pct | pct)/\(.weekly.pct | pct)" ] | join(" · ")) as $all_text
  | if $format == "pin-next" then
      ([ $s.windows | sort_by([(if .account == "default" then 0 else 1 end), .account])[] | .id | sid ]) as $order
      | ($order | index($pinned)) as $i
      | if $pinned == "" or $i == null then ($order[0] // "")
        elif $i + 1 < ($order | length) then $order[$i + 1]
        else "" end
    elif $format == "json" then $s + { lang: $lang, warn: $warn, crit: $crit } | tojson
    elif $format == "waybar" then
      (["normal", "warn", "crit"][$s.level]) as $class
      | if $s.empty then { text: "Claude —", tooltip: ("no active windows" | tr), class: "empty", alt: "empty", percentage: 0 }
        else {
          text: ((if $panel == "all" then $all_text
                  else $prefix + [ (if $s.ctx != null then "ctx \($s.ctx)%" else empty end),
                         (if $s.session != null then "\("session" | tr) \($s.session.pct)%", "\("resets" | tr) \($s.session.resets_in | dur)" else empty end),
                         (if $s.weekly != null then "\("weekly" | tr) \($s.weekly.pct)%" else empty end)
                       ] | if length == 0 then $s.model else join(" · ") end
                  end)
                 | if $theme_id == "default" then .
                   else esc | paint([$theme.normal, $theme.warn, $theme.crit][$s.level]) end),
          tooltip: ([ $s.accounts | to_entries[] | .key as $k | .value
                      | (if $k > 0 then "" else empty end),
                        (if $s.multi then "<b>\(.label | esc | paint($theme.accent))</b>" else empty end),
                        (.session | quota_line("session")),
                        (.weekly | quota_line("weekly")),
                        "\("compacts this week" | tr): \(.week_compacts)",
                        (.windows[] | "",
                          "<b>\(title | esc)</b>",
                          "\(.model // "—" | esc) · \("compacts" | tr) \(.compacts)",
                          "\("ctx" | paint($theme.label))  <tt>\(.ctx | bar)</tt>  \(.ctx | pct)  \(.tokens | tokens) / \(.window | tokens)")
                    ] | join("\n")),
          class: $class,
          alt: $class,
          percentage: ([ $s.ctx, $s.session.pct, $s.weekly.pct ] | map(num // 0) | max)
        } end
      | tojson
    elif $format == "swiftbar" then
      ([ "---", "\("Open data folder" | tr) | bash=/usr/bin/open param1=\($base) terminal=false", "\("Refresh" | tr) | refresh=true" ]) as $footer
      | if $s.empty then [ "✳ Claude —", "---", ("no active windows" | tr) + sbplain ] + $footer | join("\n")
        else [ ("✳ " + (if $panel == "all" then $all_text
                        else $prefix + [ (if $s.ctx != null then "ctx \($s.ctx)%" else empty end),
                               (if $s.session != null then "\("session" | tr) \($s.session.pct)%" else empty end),
                               (if $s.weekly != null then "\("weekly" | tr) \($s.weekly.pct)%" else empty end)
                             ] | if length == 0 then $s.model else join(" · ") end
                        end)
                  + ($s.level as $l | if $l == 0 then "" else " |" + ([0, $warn, $crit][$l] | sbcolor) end)),
               ($s.accounts[] |
                 "---",
                 (if $s.multi then "\(.label | sbesc) | size=13\(sbaccent)" else empty end),
                 (.session | sbquota("session")),
                 (.weekly | sbquota("weekly")),
                 "\("compacts this week" | tr): \(.week_compacts)\(sbplain)",
                 (.windows[] | "---",
                   "\(sbtitle) | size=13\(if .pinned then sbaccent else (0 | sbcolor) end)",
                   (if .pinned then "--\("Unpin" | tr) | bash=\($self) param1=--unpin terminal=false refresh=true"
                    else "--\("Pin to panel" | tr) | bash=\($self) param1=--pin param2=\(.id | sid) terminal=false refresh=true" end),
                   "\(.model // "—" | sbesc) · \("compacts" | tr) \(.compacts) | size=11 color=#888888",
                   "ctx  \(.ctx | blocks | add)  \(.ctx | pct)  \(.tokens | tokens) / \(.window | tokens) | font=Menlo size=12\(.ctx | sbcolor)"))
             ] + $footer | join("\n")
        end
    elif $s.empty then "Claude —"
    elif $panel == "all" then $all_text
    else $prefix + [ $s.model,
           (if $s.ctx != null then "ctx \($s.ctx)%" else empty end),
           (if $s.session != null then "\("session" | tr) \($s.session.pct)%", "\("resets" | tr) \($s.session.resets_in | dur)" else empty end),
           "\("compacts" | tr) \($s.compacts)",
           (if $s.weekly != null then "\("weekly" | tr) \($s.weekly.pct)%" else empty end)
         ] | join(" · ")
    end
' "${files[@]}")" || exit $?

if [ "$format" = "pin-next" ]; then
  if [ -n "$out" ]; then write_atomic "$PINNED" "$out"; else rm -f "$PINNED"; fi
  exit 0
fi
printf '%s\n' "$out"
