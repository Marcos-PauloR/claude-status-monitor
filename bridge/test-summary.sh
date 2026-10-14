#!/usr/bin/env bash
# Testes do resumidor. Uso: bridge/test-summary.sh
# Mesmos casos do extension/test.js (summarize), para as plataformas sem GNOME.
# Não toca no cache real: XDG_CACHE_HOME aponta para um diretório temporário.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUMMARY="$HERE/claude-status-summary.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache"
BASE="$XDG_CACHE_HOME/claude-status"
SESS="$BASE/sessions"
NOW=1760450000
export CLAUDE_STATUS_NOW=$NOW

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }
eq() { # eq <descrição> <esperado> <obtido>
  if [ "$2" == "$3" ]; then ok "$1"; else fail "$1" "esperado: [$2] obtido: [$3]"; fi
}

reset() { rm -rf "$BASE"; mkdir -p "$SESS"; }

# snap <id> <segundos atrás> [filtro jq aplicado ao snapshot base]
snap() {
  jq -nc --arg id "$1" --argjson t $((NOW - $2)) '
    { schema: 1, session_id: $id, updated_at: $t, model: "Opus 5.5", project: "proj-\($id)",
      context: { used_pct: 10, window: 200000, tokens: 20000 }, compacts: 0, limits: null }
    | '"${3:-.}" > "$SESS/$1.json"
}

# limits <session%> <weekly%> [reset session em s] [reset weekly em s]
limits() {
  printf '.limits = { five_hour: { used_pct: %s, resets_at: %s }, seven_day: { used_pct: %s, resets_at: %s } }' \
    "$1" $((NOW + ${3:-4320})) "$2" $((NOW + ${4:-259200}))
}

json() { "$SUMMARY" --format json | jq -c "$1"; }
text() { "$SUMMARY" "$@"; }

echo "== vazio (RF06)"
reset
eq "sem snapshots: json" '{"empty":true,"windows":[]}' "$(json '{empty, windows}')"
eq "sem snapshots: texto" "Claude —" "$(text)"
rm -rf "$BASE"
eq "sem diretório: texto" "Claude —" "$(text)"

echo "== inatividade (RF05)"
reset
snap a $((16 * 60))
eq "só inativos: vazio" "true" "$(json .empty)"
eq "inatividade configurável (env)" "false" "$(CLAUDE_STATUS_INACTIVE_MINUTES=20 "$SUMMARY" --format json | jq .empty)"
eq "inatividade configurável (flag)" "false" "$("$SUMMARY" --format json --inactive 20 | jq .empty)"

echo "== janela mais recente e cota (RF01, RF07)"
reset
snap old 300 '.model = "Sonnet 5.5" | '"$(limits 40 20)"
snap new 10 '.context.used_pct = 42 | .compacts = 2'
eq "model/ctx/compacts da mais recente" '["Opus 5.5",42,2]' "$(json '[.model, .ctx, .compacts]')"
eq "cota do mais recente com limits" '[40,4320,false,20]' "$(json '[.session.pct, .session.resets_in, .session.reset, .weekly.pct]')"
eq "janelas ordenadas" '["new","old"]' "$(json '[.windows[].id]')"
eq "texto" "Opus 5.5 · ctx 42% · session 40% · resets 1h12 · compacts 2 · weekly 20%" "$(text)"

reset
snap a 10 "$(limits 50 10)"
snap b 60 "$(limits 99 99)"
eq "cota vem do mais recente mesmo se menor" 50 "$(json .session.pct)"

reset
snap a 10
snap gone 3600 "$(limits 33 11)"
eq "cota de janela inativa ainda vale" '[33,11]' "$(json '[.session.pct, .weekly.pct]')"
eq "janela inativa não aparece" '["a"]' "$(json '[.windows[].id]')"

reset
snap a 10 "$(limits 80 30 -1)"
eq "reset já passou: 0% e reiniciada" '{"pct":0,"resets_in":null,"reset":true}' "$(json .session)"
eq "texto com reset passado" "Opus 5.5 · ctx 10% · session 0% · resets — · compacts 0 · weekly 30%" "$(text)"

reset
snap a 1
eq "sem limits: cotas nulas" '[null,null]' "$(json '[.session, .weekly]')"
eq "texto sem limits omite cotas" "Opus 5.5 · ctx 10% · compacts 0" "$(text)"

echo "== níveis (RF02)"
reset
snap a 1 "$(limits 75 10)"
eq "pior indicador: aviso" 1 "$(json .level)"
reset
snap a 1 '.context.used_pct = 95'
eq "ctx crítico" '[2,2]' "$(json '[.level, .windows[0].level]')"
reset
snap a 1 '.context.used_pct = 55'
eq "limiar configurável (env)" 1 "$(CLAUDE_STATUS_WARN=50 CLAUDE_STATUS_CRIT=60 "$SUMMARY" --format json | jq .level)"
eq "limiar configurável (flag)" 2 "$("$SUMMARY" --format json --warn 40 --crit 50 | jq .level)"
reset
snap a 1 '.context.used_pct = null'
eq "ctx nulo" '[null,0]' "$(json '[.ctx, .level]')"

echo "== janelas no menu (RF03)"
reset
snap a 10 '.project = "my-app" | .session_name = "core" | .context = {used_pct: 75, window: 1000000, tokens: 750000} | .compacts = 3'
eq "dados da janela" \
  '{"id":"a","project":"my-app","name":"core","model":"Opus 5.5","ctx":75,"tokens":750000,"window":1000000,"compacts":3,"level":1}' \
  "$(json '.windows[0]')"

echo "== compacts da semana (RF09)"
reset
snap a 10 "$(limits 1 1 4320 3600)"
printf '{"ts":%d}\nlixo\n{"ts":%d}\n{"ts":%d}\n' $((NOW - 86400)) $((NOW - 3600)) $((NOW - 8 * 86400)) > "$BASE/compacts.jsonl"
eq "desde seven_day.resets_at − 7 d" 2 "$(json .week_compacts)"
reset
snap a 10
printf '{"ts":%d}\n{"ts":%d}\n' $((NOW - 6 * 86400)) $((NOW - 8 * 86400)) > "$BASE/compacts.jsonl"
eq "sem limits: últimos 7 dias" 1 "$(json .week_compacts)"
reset
snap a 10 "$(limits 1 1 4320 -60)"
printf '{"ts":%d}\n{"ts":%d}\n' $((NOW - 30)) $((NOW - 120)) > "$BASE/compacts.jsonl"
eq "reset semanal passou: conta desde o reset" 1 "$(json .week_compacts)"
reset
snap a 10
eq "sem compacts.jsonl: 0" 0 "$(json .week_compacts)"

echo "== robustez"
reset
snap a 10
printf '{ quebrado' > "$SESS/broken.json"
printf '{"schema":2,"session_id":"x","updated_at":%d}\n' $NOW > "$SESS/v2.json"
printf '{"schema":1}\n' > "$SESS/noid.json"
snap tmp 0
mv "$SESS/tmp.json" "$SESS/.tmp.json.Xy12"
eq "inválido, outro schema, sem id e temporário ignorados" '["a"]' "$(json '[.windows[].id]')"
printf '5\n' > "$SESS/num.json"
printf '5\n[1]\n"x"\n{"ts":%d}\n' $NOW > "$BASE/compacts.jsonl"
eq "JSON que não é objeto (snapshot e compacts) ignorado" '[["a"],1]' "$(json '[[.windows[].id], .week_compacts]')"
eq "formato desconhecido: exit 2" 2 "$("$SUMMARY" --format nope >/dev/null 2>&1; echo $?)"

echo "== desempenho"
reset
for i in 1 2 3 4 5 6 7 8; do snap "s$i" "$i" "$(limits 10 10)"; done
start=$(date +%s)
for _ in 1 2 3 4 5 6 7 8 9 10; do "$SUMMARY" > /dev/null; done
elapsed=$(( $(date +%s) - start ))
if [ "$elapsed" -le 2 ]; then ok "10 execuções com 8 janelas em ${elapsed}s"; else fail "lento: ${elapsed}s para 10 execuções"; fi

printf '\nResultado: %d ok, %d falha(s)\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
