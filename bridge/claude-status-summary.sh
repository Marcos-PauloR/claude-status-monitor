#!/usr/bin/env bash
# Claude Status Monitor — resumidor dos snapshots para os mostradores sem GNOME.
#
# Uso: claude-status-summary.sh [--format text|json|waybar|swiftbar] [--warn N] [--crit N]
#                               [--inactive MIN] [--lang auto|en|pt]
#
# Lê ${XDG_CACHE_HOME:-~/.cache}/claude-status/{sessions/*.json,compacts.jsonl} e aplica
# as mesmas regras do painel do GNOME (extension/store.js): janelas ativas (RF05), cota do
# snapshot mais recente com limits (RF07), nível de cor (RF02) e compacts da semana (RF09).
# Precedência: flag > ambiente (CLAUDE_STATUS_WARN, _CRIT, _INACTIVE_MINUTES, _LANG) >
# ${XDG_CONFIG_HOME:-~/.config}/claude-status/config (warn=, crit=, inactive=, lang=) > padrão.
# lang=auto segue o idioma do sistema (pt_* -> português). Roda com bash 3.2 (macOS) e jq 1.6+.

BASE="${XDG_CACHE_HOME:-$HOME/.cache}/claude-status"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/claude-status/config"

die() { printf 'claude-status-summary: %s\n' "$1" >&2; exit 2; }
trim() { local v="$1"; v="${v#"${v%%[![:space:]]*}"}"; printf '%s' "${v%"${v##*[![:space:]]}"}"; }
is_num() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; }

# Config: uma chave=valor por linha, '#' comenta; valores inválidos são ignorados.
cfg_warn="" cfg_crit="" cfg_inactive="" cfg_lang=""
if [ -f "$CONFIG" ]; then
  while IFS='=' read -r key value || [ -n "$key" ]; do
    key="$(trim "$key")"; value="$(trim "${value:-}")"
    case "$key" in
      warn) is_num "$value" && cfg_warn="$value" ;;
      crit) is_num "$value" && cfg_crit="$value" ;;
      inactive) is_num "$value" && cfg_inactive="$value" ;;
      lang) case "$value" in auto|en|pt) cfg_lang="$value" ;; esac ;;
    esac
  done < "$CONFIG"
fi

format="text"
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
    *) die "opção desconhecida: $1" ;;
  esac
  shift
done

case "$format" in json|text|waybar|swiftbar) ;; *) die "formato desconhecido: $format" ;; esac
for n in "$warn" "$crit" "$inactive"; do
  is_num "$n" || die "número inválido: $n"
done
# auto: idioma do sistema (LC_ALL > LC_MESSAGES > LANG); qualquer coisa fora de pt_* é inglês.
case "$lang" in
  en|pt) ;;
  *) case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in pt*) lang="pt" ;; *) lang="en" ;; esac ;;
esac

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
  --arg lang "$lang" \
  --arg base "$BASE" \
  --arg swiftbar "${SWIFTBAR:-}" \
  --argjson now "${CLAUDE_STATUS_NOW:-$(date +%s)}" \
  --argjson warn "$warn" --argjson crit "$crit" --argjson inactive "$inactive" '
  def num: if type == "number" then . else null end;
  def tr: if $lang == "pt" then ({
      "session": "sessão", "weekly": "semana", "resets": "reinicia", "compacts": "compactações",
      "resets in": "reinicia em", "just reset": "reiniciada", "no data yet": "sem dados ainda",
      "compacts this week": "compactações na semana", "no active windows": "nenhuma janela ativa",
      "(no project)": "(sem projeto)", "Open data folder": "Abrir pasta de dados", "Refresh": "Atualizar"
    }[.] // .) else . end;
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
  def when: if .reset then ("just reset" | tr) else "\("resets in" | tr) \(.resets_in | dur)" end;
  # "900", "55k", "1M", "1.5M".
  def tokens: if num == null then "—"
      elif . >= 1000000 then "\(. / 100000 | round / 10)M"
      elif . >= 1000 then "\(. / 1000 | round)k"
      else tostring end;
  # Pango (tooltip do waybar).
  def esc: tostring | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
  def color: ["#78aeed", "#f6d32d", "#ff7b63"][level];
  # Barra de 10 posições com meio bloco: 75 -> ["███████▌", "░░"].
  def blocks: ((. // 0) | if . < 0 then 0 elif . > 100 then 100 else . end) as $p
    | ($p / 10 | floor) as $full | (if $p / 10 - $full >= 0.5 then 1 else 0 end) as $half
    | [ "\("█" * $full // "")\(if $half == 1 then "▌" else "" end)", "░" * (10 - $full - $half) // "" ];
  def bar: blocks as $b | "<span color=\"\(. // 0 | color)\">\($b[0])</span>\($b[1])";
  # SwiftBar/xbar: "|" separa parâmetros e "-" no início da linha vira submenu.
  def sbesc: tostring | gsub("\\|"; "¦") | sub("^-"; "‐");
  # Cores legíveis em barra clara; o SwiftBar aceita o par "clara,escura".
  # No macOS, item de menu sem ação aparece apagado (cinza de desativado); cor explícita evita
  # isso. Só no SwiftBar o nível 0 ganha a cor de texto normal: no xbar não há par clara/escura.
  def sbcolor: [(if $swiftbar != "" then ["#1d1d1f", "#f5f5f7"] else null end),
                ["#b8860b", "#f6d32d"], ["#d63c25", "#ff7b63"]][level]
    | if . == null then "" elif $swiftbar != "" then " color=\(.[0]),\(.[1])" else " color=\(.[0])" end;
  # Parâmetros de uma linha de texto simples (vazio no xbar).
  def sbplain: 0 | sbcolor | if . == "" then "" else " |" + . end;
  def sbquota($title): ($title | tr) as $name | ($name + "         " | .[0:9]) as $t
    | if . == null then "\($name)  \("no data yet" | tr)\(sbplain)"
      else "\($t)\(.pct | blocks | add)  \(.pct)%  \(when) | font=Menlo size=12\(.pct | sbcolor)" end;
  def pct: if . == null then "—" else "\(.)%" end;
  def quota_line($title): if . == null then "<b>\($title | tr)</b>  \("no data yet" | tr)"
      else "<b>\($title | tr)</b>  <tt>\(.pct | bar)</tt>  \(.pct)%  \(when)" end;
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
  | if $format == "json" then $s + { lang: $lang, warn: $warn, crit: $crit } | tojson
    elif $format == "waybar" then
      (["normal", "warn", "crit"][$s.level]) as $class
      | if $s.empty then { text: "Claude —", tooltip: ("no active windows" | tr), class: "empty", alt: "empty", percentage: 0 }
        else {
          text: ([ (if $s.ctx != null then "ctx \($s.ctx)%" else empty end),
                   (if $s.session != null then "\("session" | tr) \($s.session.pct)%", "\("resets" | tr) \($s.session.resets_in | dur)" else empty end),
                   (if $s.weekly != null then "\("weekly" | tr) \($s.weekly.pct)%" else empty end)
                 ] | if length == 0 then $s.model else join(" · ") end),
          tooltip: ([ ($s.session | quota_line("session")),
                      ($s.weekly | quota_line("weekly")),
                      "\("compacts this week" | tr): \($s.week_compacts)",
                      ($s.windows[] | "",
                        "<b>\([.project // ("(no project)" | tr), .name] | map(select(. != null)) | join(" — ") | esc)</b>",
                        "\(.model // "—" | esc) · \("compacts" | tr) \(.compacts)",
                        "ctx  <tt>\(.ctx | bar)</tt>  \(.ctx | pct)  \(.tokens | tokens) / \(.window | tokens)")
                    ] | join("\n")),
          class: $class,
          alt: $class,
          percentage: ([ $s.ctx, $s.session.pct, $s.weekly.pct ] | map(num // 0) | max)
        } end
      | tojson
    elif $format == "swiftbar" then
      ([ "---", "\("Open data folder" | tr) | bash=/usr/bin/open param1=\($base) terminal=false", "\("Refresh" | tr) | refresh=true" ]) as $footer
      | if $s.empty then [ "✳ Claude —", "---", ("no active windows" | tr) + sbplain ] + $footer | join("\n")
        else [ ("✳ " + ([ (if $s.ctx != null then "ctx \($s.ctx)%" else empty end),
                          (if $s.session != null then "\("session" | tr) \($s.session.pct)%" else empty end),
                          (if $s.weekly != null then "\("weekly" | tr) \($s.weekly.pct)%" else empty end)
                        ] | if length == 0 then $s.model else join(" · ") end)
                  + ($s.level as $l | if $l == 0 then "" else " |" + ([0, $warn, $crit][$l] | sbcolor) end)),
               "---",
               ($s.session | sbquota("session")),
               ($s.weekly | sbquota("weekly")),
               "\("compacts this week" | tr): \($s.week_compacts)\(sbplain)",
               ($s.windows[] | "---",
                 "\([.project // ("(no project)" | tr), .name] | map(select(. != null) | sbesc) | join(" — ")) | size=13\(0 | sbcolor)",
                 "\(.model // "—" | sbesc) · \("compacts" | tr) \(.compacts) | size=11 color=#888888",
                 "ctx  \(.ctx | blocks | add)  \(.ctx | pct)  \(.tokens | tokens) / \(.window | tokens) | font=Menlo size=12\(.ctx | sbcolor)")
             ] + $footer | join("\n")
        end
    elif $s.empty then "Claude —"
    else [ $s.model,
           (if $s.ctx != null then "ctx \($s.ctx)%" else empty end),
           (if $s.session != null then "\("session" | tr) \($s.session.pct)%", "\("resets" | tr) \($s.session.resets_in | dur)" else empty end),
           "\("compacts" | tr) \($s.compacts)",
           (if $s.weekly != null then "\("weekly" | tr) \($s.weekly.pct)%" else empty end)
         ] | join(" · ")
    end
' "${files[@]}"
