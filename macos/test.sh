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
for c in bash date env mkdir cat; do ln -s "$(command -v $c)" "$BIN/$c"; done
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
NOSUM="$TMP/nosum"; mkdir -p "$NOSUM"; for c in jq bash date env mkdir cat; do ln -s "$BIN/$c" "$NOSUM/$c"; done
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

printf '\nResultado: %d ok, %d falha(s)\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
