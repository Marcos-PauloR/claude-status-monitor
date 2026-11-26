#!/usr/bin/env bash
# Testes do plugin SwiftBar/xbar (sem macOS: lê a saída do script). Uso: macos/test.sh
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$HERE/claude-status.5s.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache"
SESS="$XDG_CACHE_HOME/claude-status/sessions"

PASS=0
FAIL=0
eq() {
  if [ "$2" == "$3" ]; then PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL + 1)); printf '  FAIL %s\n       esperado: [%s] obtido: [%s]\n' "$1" "$2" "$3"; fi
}

# Simula o PATH mínimo do SwiftBar: só um diretório com o resumidor e o jq.
BIN="$TMP/bin"; mkdir -p "$BIN"
ln -s "$HERE/../bridge/claude-status-summary.sh" "$BIN/claude-status-summary.sh"
ln -s "$(command -v jq)" "$BIN/jq"
for c in bash date env mkdir cat dirname basename mktemp mv rm; do ln -s "$(command -v $c)" "$BIN/$c"; done
run() { OUT="$(env -i HOME="$TMP/home" XDG_CACHE_HOME="$XDG_CACHE_HOME" PATH="$1" "$(command -v bash)" "$PLUGIN" 2>&1)"; RC=$?; }

echo "== vazio"
run "$BIN"
eq "exit 0" 0 "$RC"
eq "título" "✳ Claude —" "$(head -1 <<<"$OUT")"
eq "menu" "no active windows" "$(sed -n 3p <<<"$OUT")"

echo "== com janela"
mkdir -p "$SESS"
jq -nc --argjson t "$(date +%s)" '{schema:1, session_id:"a", updated_at:$t, model:"Opus 5.5", project:"p",
  context:{used_pct:95, window:200000, tokens:190000}, limits:null}' > "$SESS/a.json"
run "$BIN"
eq "título crítico" "✳ ctx 95% | color=#d63c25" "$(head -1 <<<"$OUT")"
eq "janela no menu" "p | size=13" "$(grep -m1 '^p |' <<<"$OUT")"

echo "== resumidor achado em ~/.local/bin (PATH do próprio plugin)"
mkdir -p "$TMP/home/.local/bin"
ln -s "$HERE/../bridge/claude-status-summary.sh" "$TMP/home/.local/bin/claude-status-summary.sh"
NOSUM="$TMP/nosum"; mkdir -p "$NOSUM"; for c in jq bash date env mkdir cat dirname basename mktemp mv rm; do ln -s "$BIN/$c" "$NOSUM/$c"; done
run "$NOSUM"
eq "acha em ~/.local/bin" "✳ ctx 95% | color=#d63c25" "$(head -1 <<<"$OUT")"

echo "== dependências ausentes"
rm "$TMP/home/.local/bin/claude-status-summary.sh"
EMPTY="$TMP/empty"; mkdir -p "$EMPTY"; ln -s "$BIN/bash" "$EMPTY/bash"
run "$EMPTY"
eq "exit 0" 0 "$RC"
eq "título de erro" "✳ Claude ?" "$(head -1 <<<"$OUT")"
eq "explica o resumidor" "true" "$(grep -q 'claude-status-summary.sh not found' <<<"$OUT" && echo true || echo false)"
if [ ! -x /opt/homebrew/bin/jq ] && [ ! -x /usr/local/bin/jq ]; then
  eq "explica o jq" "true" "$(grep -q 'jq not found' <<<"$OUT" && echo true || echo false)"
fi

echo "== duas contas: seções e fixar pelo menu"
rm -rf "$XDG_CACHE_HOME"; mkdir -p "$SESS"
for a in default work; do
  jq -nc --arg a "$a" --argjson t "$(date +%s)" '{schema:1, session_id:("s-"+$a), account:$a, updated_at:$t, model:"Opus 5.5", project:"my-app",
    context:{used_pct:42, window:200000, tokens:80000},
    limits:{five_hour:{used_pct:30, resets_at:($t+3600)}, seven_day:{used_pct:10, resets_at:($t+90000)}}}' > "$SESS/s-$a.json"
done
run "$BIN"
eq "cabeçalho da conta default" "1" "$(grep -c '^default | size=13' <<<"$OUT")"
eq "cabeçalho da conta work" "1" "$(grep -c '^work | size=13' <<<"$OUT")"
eq "sem fixada: nenhum 📌" "0" "$(grep -c '📌' <<<"$OUT")"
PINLINE="$(grep -m1 'param2=s-work ' <<<"$OUT")"
eq "linha de fixar" "true" "$(grep -q '^--Pin to panel | bash=.* param1=--pin param2=s-work terminal=false refresh=true$' <<<"$PINLINE" && echo true || echo false)"
# Executa o comando da linha como o SwiftBar: bash=<script> param1=… param2=…
PBASH="${PINLINE#*bash=}"; PBASH="${PBASH%% param1=*}"
P1="${PINLINE#* param1=}"; P1="${P1%% *}"
P2="${PINLINE#* param2=}"; P2="${P2%% *}"
env -i HOME="$TMP/home" XDG_CACHE_HOME="$XDG_CACHE_HOME" PATH="$BIN" "$(command -v bash)" "$PBASH" "$P1" "$P2"
eq "criou o pinned" "s-work" "$(cat "$XDG_CACHE_HOME/claude-status/pinned" 2>/dev/null)"
run "$BIN"
# o título da barra não leva o 📌 (só o item da janela no menu); o foco passa para a conta fixada
eq "título segue a janela fixada" "true" "$(head -1 <<<"$OUT" | grep -q '^✳ work · ctx 42%' && echo true || echo false)"
eq "janela fixada com 📌 no menu" "1" "$(grep -c '^📌 my-app | size=13' <<<"$OUT")"
UNPIN="$(grep -m1 'param1=--unpin' <<<"$OUT")"
eq "linha de desafixar" "true" "$(grep -q '^--Unpin | bash=.* param1=--unpin terminal=false refresh=true$' <<<"$UNPIN" && echo true || echo false)"
PBASH="${UNPIN#*bash=}"; PBASH="${PBASH%% param1=*}"
env -i HOME="$TMP/home" XDG_CACHE_HOME="$XDG_CACHE_HOME" PATH="$BIN" "$(command -v bash)" "$PBASH" --unpin
eq "desafixou" "false" "$([ -e "$XDG_CACHE_HOME/claude-status/pinned" ] && echo true || echo false)"
run "$BIN"
eq "sem 📌 de novo" "0" "$(grep -c '📌' <<<"$OUT")"

printf '\nResultado: %d ok, %d falha(s)\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
