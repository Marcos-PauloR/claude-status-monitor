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
# Isola do ambiente de quem roda os testes: sem config, idioma inglês.
export XDG_CONFIG_HOME="$TMP/config"
CONF="$XDG_CONFIG_HOME/claude-status/config"
THEMES="$XDG_CONFIG_HOME/claude-status/themes"
export XDG_DATA_HOME="$TMP/data"
export LANG=C
unset LC_ALL LC_MESSAGES CLAUDE_STATUS_LANG CLAUDE_STATUS_WARN CLAUDE_STATUS_CRIT CLAUDE_STATUS_INACTIVE_MINUTES
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
conf() { mkdir -p "$(dirname "$CONF")"; printf '%s\n' "$@" > "$CONF"; }

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
eq "sem snapshots: json com idioma e limiares (T14)" '["en",70,90]' "$(json '[.lang, .warn, .crit]')"
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
  '{"id":"a","account":"default","project":"my-app","name":"core","model":"Opus 5.5","ctx":75,"tokens":750000,"window":1000000,"compacts":3,"level":1,"pinned":false}' \
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

echo "== --format waybar (T8)"
wb() { "$SUMMARY" --format waybar | jq -r "$1"; }
reset
eq "vazio: texto e classe" '["Claude —","empty","no active windows",0]' "$("$SUMMARY" --format waybar | jq -c '[.text, .class, .tooltip, .percentage]')"
reset
snap a 10 '.project = "my-app & Co" | .session_name = "<core>" | .context = {used_pct: 75, window: 1000000, tokens: 750000} | .compacts = 3 | '"$(limits 31 92)"
snap b 60 '.model = "Sonnet 5.5"'
printf '{"ts":%d}\n' $((NOW - 60)) > "$BASE/compacts.jsonl"
eq "texto" "ctx 75% · session 31% · resets 1h12 · weekly 92%" "$(wb .text)"
eq "classe = pior nível" "crit" "$(wb .class)"
eq "alt = classe" "crit" "$(wb .alt)"
eq "percentage = pior indicador" 92 "$(wb .percentage)"
tip="$(wb .tooltip)"
eq "tooltip: cota session" "true" "$(grep -q 'session.*31%.*resets in 1h12' <<<"$tip" && echo true || echo false)"
eq "tooltip: compacts da semana" "true" "$(grep -q 'compacts this week: 1' <<<"$tip" && echo true || echo false)"
eq "tooltip: janela com Pango escapado" "true" "$(grep -qF 'my-app &amp; Co — &lt;core&gt;' <<<"$tip" && echo true || echo false)"
eq "tooltip: ctx com tokens" "true" "$(grep -q '75%.*750k / 1M' <<<"$tip" && echo true || echo false)"
eq "tooltip: segunda janela" "true" "$(grep -q 'Sonnet 5.5 · compacts 0' <<<"$tip" && echo true || echo false)"
eq "tooltip: barra de 10 posições" "true" "$(grep -q '███████▌</span>░░' <<<"$tip" && echo true || echo false)"
if command -v python3 >/dev/null; then
  eq "tooltip é Pango válido (xml)" "true" "$(printf '<r>%s</r>' "$tip" | python3 -c 'import sys,xml.dom.minidom as m; m.parseString(sys.stdin.read())' 2>/dev/null && echo true || echo false)"
fi
reset
snap a 10 "$(limits 80 30 -1)"
eq "reset passado no tooltip" "true" "$(wb .tooltip | grep -q 'session.*0%.*just reset' && echo true || echo false)"
eq "classe normal" "normal" "$(wb .class)"
reset
snap a 1 '.context.used_pct = null'
eq "sem dados: percentage 0" '[0,"normal"]' "$("$SUMMARY" --format waybar | jq -c '[.percentage, .class]')"

echo "== --format swiftbar (T9)"
sb() { "$SUMMARY" --format swiftbar; }
reset
eq "vazio: título" "✳ Claude —" "$(sb | head -1)"
eq "vazio: menu" "no active windows" "$(sb | sed -n 3p)"
reset
snap a 10 '.project = "proj|x" | .session_name = "--sub" | .context = {used_pct: 75, window: 1000000, tokens: 750000} | .compacts = 3 | '"$(limits 31 92)"
snap b 60 '.model = "Sonnet 5.5"'
printf '{"ts":%d}\n' $((NOW - 60)) > "$BASE/compacts.jsonl"
out="$(sb)"
eq "título curto com cor crítica" "✳ ctx 75% · session 31% · weekly 92% | color=#d63c25" "$(sed -n 1p <<<"$out")"
eq "separador" "---" "$(sed -n 2p <<<"$out")"
eq "cota session" "session  ███░░░░░░░  31%  resets in 1h12 | font=Menlo size=12" "$(sed -n 3p <<<"$out")"
eq "cota weekly com cor" "weekly   █████████░  92%  resets in 3d0h | font=Menlo size=12 color=#d63c25" "$(sed -n 4p <<<"$out")"
eq "compacts da semana" "compacts this week: 1" "$(sed -n 5p <<<"$out")"
eq "título da janela escapa | e --" "proj¦x — ‐-sub | size=13" "$(grep -m1 'proj' <<<"$out")"
eq "ctx da janela" "ctx  ███████▌░░  75%  750k / 1M | font=Menlo size=12 color=#b8860b" "$(grep -m1 '^ctx  ███████' <<<"$out")"
eq "segunda janela" "true" "$(grep -q '^Sonnet 5.5 · compacts 0 | size=11 color=#888888$' <<<"$out" && echo true || echo false)"
eq "abrir pasta" "Open data folder | bash=/usr/bin/open param1=$BASE terminal=false" "$(grep '^Open data folder' <<<"$out")"
eq "atualizar" "Refresh | refresh=true" "$(tail -1 <<<"$out")"
eq "nenhuma linha de conteúdo começa com -- (só as ações de submenu Fixar/Desafixar)" "0" "$(grep '^--[^-]' <<<"$out" | grep -vc '^--\(Pin to panel\|Unpin\) | bash=')"
eq "SwiftBar: cor clara/escura" "✳ ctx 75% · session 31% · weekly 92% | color=#d63c25,#ff7b63" "$(SWIFTBAR=1 "$SUMMARY" --format swiftbar | head -1)"
reset
snap a 10 "$(limits 10 10)"
eq "título normal sem cor" "✳ ctx 10% · session 10% · weekly 10%" "$(sb | head -1)"
sbo="$(SWIFTBAR=1 "$SUMMARY" --format swiftbar)"
N="color=#1d1d1f,#f5f5f7"
eq "SwiftBar: título da barra sem cor fixa" "✳ ctx 10% · session 10% · weekly 10%" "$(head -1 <<<"$sbo")"
eq "SwiftBar: cota normal com cor de texto (não fica apagada)" "session  █░░░░░░░░░  10%  resets in 1h12 | font=Menlo size=12 $N" "$(sed -n 3p <<<"$sbo")"
eq "SwiftBar: compacts da semana com cor de texto" "compacts this week: 0 | $N" "$(sed -n 5p <<<"$sbo")"
eq "SwiftBar: título da janela com cor de texto" "proj-a | size=13 $N" "$(grep -m1 '^proj-a' <<<"$sbo")"
eq "SwiftBar: ctx normal com cor de texto" "true" "$(grep -q "^ctx .* $N\$" <<<"$sbo" && echo true || echo false)"
eq "SwiftBar: modelo mantém o cinza" "true" "$(grep -q '^Opus 5.5 · compacts 0 | size=11 color=#888888$' <<<"$sbo" && echo true || echo false)"
eq "SwiftBar: ações sem cor" "Refresh | refresh=true" "$(tail -1 <<<"$sbo")"
eq "xbar: linhas sem cor fixa" "0" "$(sb | grep -c '1d1d1f')"
reset
snap a 10 "$(limits 80 30 -1)"
eq "reset passado" "session  ░░░░░░░░░░  0%  just reset | font=Menlo size=12" "$(sb | sed -n 3p)"
reset
snap a 10
eq "sem limits" "session  no data yet" "$(sb | sed -n 3p)"

echo "== config único (T12)"
reset
snap a 1 '.context.used_pct = 55'
conf '# limiares' 'warn=50' ' crit = 60 ' 'desconhecida=1'
eq "warn/crit do config (com comentário, espaços e chave desconhecida)" 1 "$(json .level)"
conf 'warn=40' 'crit=50'
eq "crit do config" 2 "$(json .level)"
eq "ambiente vence o config" 1 "$(CLAUDE_STATUS_CRIT=60 "$SUMMARY" --format json | jq .level)"
eq "flag vence ambiente e config" 0 "$(CLAUDE_STATUS_WARN=10 "$SUMMARY" --format json --warn 80 --crit 95 | jq .level)"
eq "json traz os limiares do config (T14)" '[40,50]' "$(json '[.warn, .crit]')"
eq "json traz os limiares da flag (T14)" '[80,95]' "$("$SUMMARY" --format json --warn 80 --crit 95 | jq -c '[.warn, .crit]')"
conf 'warn=abc' 'crit=' 'inactive=-3'
eq "valor inválido no config cai no padrão" '[0,false]' "$("$SUMMARY" --format json | jq -c '[.level, .empty]')"
reset
snap a 120
conf 'inactive=1'
eq "inactive do config" true "$(json .empty)"
rm -f "$CONF"

echo "== idioma (T12)"
reset
snap old 300 '.model = "Sonnet 5.5" | '"$(limits 40 20)"
snap new 10 '.context.used_pct = 42 | .compacts = 2 | .project = null'
EN="Opus 5.5 · ctx 42% · session 40% · resets 1h12 · compacts 2 · weekly 20%"
PT="Opus 5.5 · ctx 42% · sessão 40% · reinicia 1h12 · compactações 2 · semana 20%"
eq "padrão (LANG=C): inglês" "$EN" "$(text)"
eq "auto com LANG=pt_BR: português" "$PT" "$(LANG=pt_BR.UTF-8 "$SUMMARY")"
eq "auto com LANG=en_US: inglês" "$EN" "$(LANG=en_US.UTF-8 "$SUMMARY")"
eq "LC_ALL vence LANG" "$EN" "$(LANG=pt_BR.UTF-8 LC_ALL=en_US.UTF-8 "$SUMMARY")"
conf 'lang=pt'
eq "lang=pt no config" "$PT" "$(text)"
eq "lang do ambiente vence o config" "$EN" "$(CLAUDE_STATUS_LANG=en "$SUMMARY")"
eq "--lang vence tudo" "$EN" "$("$SUMMARY" --lang en)"
eq "--lang inválido: exit 2" 2 "$("$SUMMARY" --lang xx >/dev/null 2>&1; echo $?)"
eq "json traz o idioma do config (T14)" '"pt"' "$(json .lang)"
eq "json: --lang vence o config (T14)" '"en"' "$("$SUMMARY" --format json --lang en | jq .lang)"
eq "json: auto vira o idioma resolvido (T14)" '"pt"' "$(rm -f "$CONF"; LANG=pt_BR.UTF-8 "$SUMMARY" --format json | jq .lang)"
conf 'lang=pt'
eq "json não traduz chaves" '["session","weekly"]' "$(json '[keys[] | select(. == "session" or . == "weekly")]')"
eq "waybar em pt" "ctx 42% · sessão 40% · reinicia 1h12 · semana 20%" "$("$SUMMARY" --format waybar | jq -r .text)"
tip="$("$SUMMARY" --format waybar | jq -r .tooltip)"
eq "tooltip em pt" "true" "$(grep -q 'sessão.*reinicia em 1h12' <<<"$tip" && grep -q 'compactações na semana: 0' <<<"$tip" && grep -q '(sem projeto)' <<<"$tip" && echo true || echo false)"
out="$("$SUMMARY" --format swiftbar)"
eq "swiftbar em pt" "true" "$(grep -q '^Abrir pasta de dados |' <<<"$out" && grep -q '^Atualizar | refresh=true' <<<"$out" && grep -q '^semana   █' <<<"$out" && echo true || echo false)"
reset
snap a 10 "$(limits 80 30 -1)"
eq "reiniciada em pt" "true" "$("$SUMMARY" --format swiftbar | grep -q 'reiniciada' && echo true || echo false)"
reset
eq "vazio em pt" '["Claude —","nenhuma janela ativa"]' "$("$SUMMARY" --format waybar | jq -c '[.text, .tooltip]')"
snap a 1
eq "sem limits em pt" "true" "$("$SUMMARY" --format swiftbar | grep -q '^sessão  sem dados ainda$' && echo true || echo false)"
eq "SwiftBar: sem dados com cor de texto" "true" "$(SWIFTBAR=1 "$SUMMARY" --format swiftbar | grep -q '^sessão  sem dados ainda | color=#1d1d1f,#f5f5f7$' && echo true || echo false)"
reset
eq "SwiftBar: nenhuma janela com cor de texto" "nenhuma janela ativa | color=#1d1d1f,#f5f5f7" "$(SWIFTBAR=1 "$SUMMARY" --format swiftbar | sed -n 3p)"
rm -f "$CONF"

echo "== contas (v1.3)"
reset
snap d1 10 '.context.used_pct = 42 | '"$(limits 31 12)"
snap w1 20 '.account = "work" | .model = "Sonnet 5.5" | '"$(limits 78 40)"
snap w2 30 '.account = "work"'
eq "contas: default primeiro" '["default","work"]' "$(json '[.accounts[].id]')"
eq "cota por conta" '[[31,12],[78,40]]' "$(json '[.accounts[] | [.session.pct, .weekly.pct]]')"
eq "janelas por conta" '[["d1"],["w1","w2"]]' "$(json '[.accounts[] | [.windows[].id]]')"
eq "janela traz a conta" '["default","work","work"]' "$(json '[.windows[].account]')"
eq "topo = janela em foco e sua conta" '["d1",42,31,12]' "$(json '[.focus.id, .ctx, .session.pct, .weekly.pct]')"
eq "multi" 'true' "$(json .multi)"
eq "nível por conta" '[0,1]' "$(json '[.accounts[].level]')"
eq "texto focus com conta" "default · Opus 5.5 · ctx 42% · session 31% · resets 1h12 · compacts 0 · weekly 12%" "$(text)"
eq "texto all" "Opus 5.5 · ctx 42% · default 31%/12% · work 78%/40%" "$(text --panel-accounts all)"
conf 'account.work=Trabalho' 'panel_accounts=all'
eq "apelido" '["default","Trabalho"]' "$(json '[.accounts[].label]')"
eq "panel_accounts do config" "Opus 5.5 · ctx 42% · default 31%/12% · Trabalho 78%/40%" "$(text)"
eq "--panel-accounts vence o config" '"focus"' "$("$SUMMARY" --format json --panel-accounts focus | jq .panel_accounts)"
eq "--panel-accounts inválido: exit 2" 2 "$("$SUMMARY" --panel-accounts xx >/dev/null 2>&1; echo $?)"
rm -f "$CONF"
printf '{"ts":%d,"session_id":"d1"}\n{"ts":%d,"session_id":"w1","account":"work"}\n{"ts":%d,"session_id":"w2","account":"work"}\n' \
  $NOW $NOW $NOW > "$BASE/compacts.jsonl"
eq "compacts da semana por conta" '[1,2]' "$(json '[.accounts[].week_compacts]')"
eq "topo: compacts da semana da conta em foco" 1 "$(json .week_compacts)"
tip="$("$SUMMARY" --format waybar | jq -r .tooltip)"
eq "tooltip: cabeçalho por conta" "true" "$(grep -q '^<b>default</b>$' <<<"$tip" && grep -q '^<b>work</b>$' <<<"$tip" && echo true || echo false)"
eq "waybar all" "Opus 5.5 · ctx 42% · default 31%/12% · work 78%/40%" "$("$SUMMARY" --format waybar --panel-accounts all | jq -r .text)"
out="$("$SUMMARY" --format swiftbar)"
eq "swiftbar: cabeçalho por conta" "true" "$(grep -q '^default | size=13' <<<"$out" && grep -q '^work | size=13' <<<"$out" && echo true || echo false)"

reset
snap d1 10
snap wold 3600 '.account = "work" | '"$(limits 50 50)"
eq "conta sem janela ativa mas com cota aparece" '[["default",1],["work",0]]' "$(json '[.accounts[] | [.id, (.windows | length)]]')"
reset
snap d1 10
snap wold 3600 '.account = "work" | '"$(limits 50 50 -1 -1)"
eq "conta sem janela e com cota resetada some" '["default"]' "$(json '[.accounts[].id]')"
eq "uma conta: multi false" 'false' "$(json .multi)"
eq "uma conta: texto igual à v1.2" "Opus 5.5 · ctx 10% · compacts 0" "$(text)"

echo "== janela fixada (v1.3)"
reset
snap a 10 '.context.used_pct = 42'
snap b 20 '.context.used_pct = 7'
eq "--pin: exit 0 sem saída" "0:" "$("$SUMMARY" --pin b; echo "$?:")"
eq "--pin grava o id" "b" "$(cat "$BASE/pinned")"
eq "foco = fixada" '["b",7,"b"]' "$(json '[.focus.id, .ctx, .pinned]')"
eq "janela fixada marcada" '[false,true]' "$(json '[.windows[].pinned]')"
eq "texto usa a fixada" "Opus 5.5 · ctx 7% · compacts 0" "$(text)"
out="$("$SUMMARY" --format swiftbar)"
eq "swiftbar: 📌 e ação Desafixar" "true" "$(grep -q '^📌 proj-b' <<<"$out" && grep -qF -- "--Unpin | bash=$SUMMARY param1=--unpin terminal=false refresh=true" <<<"$out" && echo true || echo false)"
eq "swiftbar: ação Fixar nas outras" "true" "$(grep -qF -- "--Pin to panel | bash=$SUMMARY param1=--pin param2=a terminal=false refresh=true" <<<"$out" && echo true || echo false)"
eq "tooltip: 📌 na fixada" "true" "$("$SUMMARY" --format waybar | jq -r .tooltip | grep -q '^<b>📌 proj-b</b>$' && echo true || echo false)"
"$SUMMARY" --unpin
eq "--unpin apaga" "false" "$([ -e "$BASE/pinned" ] && echo true || echo false)"
eq "--unpin sem arquivo: exit 0" 0 "$("$SUMMARY" --unpin; echo $?)"
printf 'sumiu\n' > "$BASE/pinned"
eq "órfã: foco = mais recente" '["a",null]' "$(json '[.focus.id, .pinned]')"
eq "órfã: arquivo apagado" "false" "$([ -e "$BASE/pinned" ] && echo true || echo false)"
snap b 3600
printf 'b\n' > "$BASE/pinned"
eq "fixada inativa: ignorada e apagada" '"a"/false' "$(json .focus.id)/$([ -e "$BASE/pinned" ] && echo true || echo false)"
: > "$BASE/pinned"
eq "pinned vazio: sem fixação" '"a"' "$(json .focus.id)"
eq "--pin sem id: exit 2" 2 "$("$SUMMARY" --pin >/dev/null 2>&1; echo $?)"
"$SUMMARY" --pin 'a/../b'
eq "--pin saneia o id" "a____b" "$(cat "$BASE/pinned")"

reset
snap d1 10
snap d2 20
snap w1 5 '.account = "work"'
order=""
for _ in 1 2 3 4 5; do
  "$SUMMARY" --pin-next
  order="$order $(cat "$BASE/pinned" 2>/dev/null || echo -)"
done
eq "--pin-next: por conta, depois mais recente; após a última desafixa" " d1 d2 w1 - d1" "$order"

echo "== temas (v1.3)"
reset
snap a 10 "$(limits 80 20)"
eq "padrão: default" '{"id":"default","name":"Default","normal":"","warn":"#f6d32d","crit":"#ff7b63","label":"","bar":"#78aeed","accent":""}' "$(json .theme)"
eq "embutido via flag" '["nord","Nord","#ebcb8b"]' "$("$SUMMARY" --format json --theme nord | jq -c '[.theme.id, .theme.name, .theme.warn]')"
conf 'theme=dracula'
eq "tema do config" '"Dracula"' "$(json .theme.name)"
mkdir -p "$THEMES"
printf 'name=Meu Dracula\nwarn=#123\n' > "$THEMES/dracula.theme"
eq "o da pessoa vence o embutido; chave ausente vem do default" '["Meu Dracula","#123","#ff7b63"]' "$(json '[.theme.name, .theme.warn, .theme.crit]')"
printf 'name=Ruim\nwarn=amarelo\ncrit=#12345\n' > "$THEMES/ruim.theme"
conf 'theme=ruim'
eq "cor inválida vira a do default" '["#f6d32d","#ff7b63"]' "$(json '[.theme.warn, .theme.crit]' 2>/dev/null)"
eq "cor inválida gera log" "true" "$("$SUMMARY" --format json 2>&1 >/dev/null | grep -q 'cor inválida em warn' && echo true || echo false)"
conf 'theme=naoexiste'
eq "tema inexistente: default" '"default"' "$(json .theme.id 2>/dev/null)"
eq "tema inexistente: log e exit 0" "true/0" "$("$SUMMARY" 2>&1 >/dev/null | grep -q 'tema não encontrado: naoexiste' && echo true || echo false)/$("$SUMMARY" >/dev/null 2>&1; echo $?)"
conf 'theme=nord'
eq "waybar: texto com a cor do nível" '<span color="#ebcb8b">ctx 10% · session 80% · resets 1h12 · weekly 20%</span>' "$("$SUMMARY" --format waybar | jq -r .text)"
eq "waybar: barra normal com a cor bar" "true" "$("$SUMMARY" --format waybar | jq -r .tooltip | grep -q 'span color="#5e81ac"' && echo true || echo false)"
eq "swiftbar: cor do tema (mesma nos dois modos)" "true" "$(SWIFTBAR=1 "$SUMMARY" --format swiftbar | grep -q '^session  .* color=#ebcb8b$' && echo true || echo false)"
rm -f "$CONF"
eq "--list-themes: default primeiro, sem repetir" '["default","catppuccin","dracula","nord","ruim","solarized"]' "$("$SUMMARY" --list-themes | jq -c 'map(.id)')"
eq "--list-themes: nome do arquivo da pessoa" '"Meu Dracula"' "$("$SUMMARY" --list-themes | jq -c '.[] | select(.id == "dracula") | .name')"
rm -rf "$THEMES"

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
