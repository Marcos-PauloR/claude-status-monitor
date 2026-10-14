#!/usr/bin/env bash
# Claude Status Monitor — instala a ponte statusline.
#
# Uso: ./install.sh              instala/atualiza (idempotente)
#      ./install.sh --uninstall  remove a ponte e as entradas do settings.json
#
# - Copia bridge/claude-status-bridge.sh para ~/.local/bin.
# - Faz merge de statusLine e dos hooks PreCompact/SessionEnd em ~/.claude/settings.json,
#   sempre com backup (settings.json.bak-AAAAMMDD-HHMMSS) antes de alterar.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
BRIDGE="$BIN_DIR/claude-status-bridge.sh"
SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
MARK="claude-status-bridge.sh"   # identifica as entradas criadas por este instalador

die() { printf 'erro: %s\n' "$1" >&2; exit 1; }

command -v jq >/dev/null || die "jq não encontrado (sudo dnf install jq)"

mode="install"
case "${1:-}" in
  "") ;;
  --uninstall) mode="uninstall" ;;
  *) die "opção desconhecida: $1" ;;
esac

current="{}"
if [ -f "$SETTINGS" ]; then
  jq -e 'type == "object"' "$SETTINGS" >/dev/null 2>&1 || die "$SETTINGS não é um JSON válido; nada foi alterado"
  current="$(cat "$SETTINGS")"
fi

# Remove de todos os eventos os grupos de hook que chamam a ponte; eventos vazios somem.
strip='
  def ours: (.command? // "") | contains($mark);
  (if (.statusLine | (.command? // "") | contains($mark)) then del(.statusLine) else . end)
  | if .hooks then
      .hooks |= (with_entries(.value |= (map(if (.hooks | type) == "array"
                                              then .hooks |= map(select(ours | not)) else . end)
                                          | map(select((.hooks | type) != "array" or (.hooks | length > 0)))))
                 | with_entries(select(.value | length > 0)))
      | if .hooks == {} then del(.hooks) else . end
    else . end
'

if [ "$mode" = "install" ]; then
  previous="$(jq -r '.statusLine.command // empty' <<<"$current")"
  updated="$(jq --arg mark "$MARK" --arg cmd "$BRIDGE" "$strip"'
    | .statusLine = { type: "command", command: $cmd, padding: 0 }
    | .hooks.PreCompact += [{ hooks: [{ type: "command", command: "\($cmd) --compact" }] }]
    | .hooks.SessionEnd += [{ hooks: [{ type: "command", command: "\($cmd) --end" }] }]
  ' <<<"$current")"
else
  updated="$(jq --arg mark "$MARK" "$strip" <<<"$current")"
fi

if [ "$mode" = "install" ]; then
  mkdir -p "$BIN_DIR"
  install -m 755 "$HERE/bridge/claude-status-bridge.sh" "$BRIDGE"
  echo "ponte instalada em $BRIDGE"
else
  rm -f "$BRIDGE"
  echo "ponte removida de $BRIDGE"
fi

if [ "$(jq -S . <<<"$current")" = "$(jq -S . <<<"$updated")" ]; then
  echo "$SETTINGS já está atualizado; nada a fazer"
  exit 0
fi

mkdir -p "$(dirname "$SETTINGS")"
if [ -f "$SETTINGS" ]; then
  backup="$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
  cp -p "$SETTINGS" "$backup"
  echo "backup: $backup"
fi

tmp="$(mktemp "$SETTINGS.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
printf '%s\n' "$updated" > "$tmp"
[ -f "$SETTINGS" ] && chmod --reference="$SETTINGS" "$tmp"
mv -f "$tmp" "$SETTINGS"
trap - EXIT

if [ "$mode" = "install" ]; then
  [ -n "${previous:-}" ] && [[ "$previous" != *"$MARK"* ]] &&
    echo "aviso: a statusLine anterior ($previous) foi substituída; ela está no backup"
  echo "$SETTINGS atualizado: statusLine + hooks PreCompact e SessionEnd"
  echo "abra uma nova sessão do Claude Code para ativar"
else
  echo "$SETTINGS: entradas da ponte removidas"
fi
