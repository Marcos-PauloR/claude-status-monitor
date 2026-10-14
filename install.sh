#!/usr/bin/env bash
# Claude Status Monitor — instalador.
#
# Uso: ./install.sh [--target ALVO]... [--plugin-dir DIR]   instala/atualiza (idempotente)
#      ./install.sh --uninstall [--target ALVO]...         remove
#
# Sempre: copia a ponte e o resumidor (bridge/claude-status-{bridge,summary}.sh) para
# ~/.local/bin e faz merge de statusLine e dos hooks PreCompact/SessionEnd em
# ~/.claude/settings.json, com backup (settings.json.bak-AAAAMMDD-HHMMSS) antes de alterar.
#
# Alvos (mostrador de cada plataforma; pode repetir --target):
#   gnome   compila o schema, cria o symlink da extensão e a ativa
#   waybar  copia waybar/claude-status-waybar.sh para ~/.local/bin
#   macos   copia o plugin para a pasta do SwiftBar/xbar (ou --plugin-dir DIR)
#   kde     instala/atualiza o plasmoid com kpackagetool6
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
BRIDGE="$BIN_DIR/claude-status-bridge.sh"
SUMMARY="$BIN_DIR/claude-status-summary.sh"
SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
MARK="claude-status-bridge.sh"   # identifica as entradas criadas por este instalador

GNOME_UUID="claude-status@marcospaulo"
GNOME_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$GNOME_UUID"
WAYBAR_MODULE="$BIN_DIR/claude-status-waybar.sh"
MACOS_PLUGIN="claude-status.5s.sh"
MACOS_MARK="plugin SwiftBar/xbar"  # identifica o plugin deste projeto, mesmo renomeado
KDE_ID="org.claudestatus.monitor"

die() { printf 'erro: %s\n' "$1" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() { sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

mode="install"
targets=()
plugin_dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    --uninstall) mode="uninstall" ;;
    --target)
      case "${2:-}" in
        gnome|waybar|macos|kde) targets+=("$2") ;;
        *) die "alvo inválido: '${2:-}' (use gnome, waybar, macos ou kde)" ;;
      esac
      shift ;;
    --plugin-dir) plugin_dir="${2:-}"; [ -n "$plugin_dir" ] || die "--plugin-dir precisa de um diretório"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "opção desconhecida: $1 (veja --help)" ;;
  esac
  shift
done

have jq || die "jq não encontrado (Fedora: sudo dnf install jq · macOS: brew install jq · Debian/Ubuntu: sudo apt install jq)"

# ---------------------------------------------------------------- settings.json

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

current="{}"
if [ -f "$SETTINGS" ]; then
  jq -e 'type == "object"' "$SETTINGS" >/dev/null 2>&1 || die "$SETTINGS não é um JSON válido; nada foi alterado"
  current="$(cat "$SETTINGS")"
fi

update_settings() {
  local previous="" updated backup tmp
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

  if [ "$(jq -S . <<<"$current")" = "$(jq -S . <<<"$updated")" ]; then
    echo "$SETTINGS já está atualizado; nada a fazer"
    return 0
  fi

  mkdir -p "$(dirname "$SETTINGS")"
  if [ -f "$SETTINGS" ]; then
    backup="$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
    cp -p "$SETTINGS" "$backup"
    echo "backup: $backup"
  fi

  tmp="$(mktemp "$SETTINGS.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT
  # cp -p copia a permissão do original (portável: chmod --reference não existe no macOS).
  if [ -f "$SETTINGS" ]; then cp -p "$SETTINGS" "$tmp"; fi
  printf '%s\n' "$updated" > "$tmp"
  mv -f "$tmp" "$SETTINGS"
  trap - EXIT

  if [ "$mode" = "install" ]; then
    if [ -n "$previous" ] && [[ "$previous" != *"$MARK"* ]]; then
      echo "aviso: a statusLine anterior ($previous) foi substituída; ela está no backup"
    fi
    echo "$SETTINGS atualizado: statusLine + hooks PreCompact e SessionEnd"
    echo "abra uma nova sessão do Claude Code para ativar"
  else
    echo "$SETTINGS: entradas da ponte removidas"
  fi
}

# ---------------------------------------------------------------- alvos

gnome_install() {
  have glib-compile-schemas || die "glib-compile-schemas não encontrado (Fedora: sudo dnf install glib2-devel)"
  glib-compile-schemas "$HERE/extension/schemas"
  if [ -L "$GNOME_DIR" ] && [ "$(readlink "$GNOME_DIR")" = "$HERE/extension" ]; then
    echo "gnome: extensão já aponta para $HERE/extension"
  elif [ -e "$GNOME_DIR" ] || [ -L "$GNOME_DIR" ]; then
    die "gnome: $GNOME_DIR já existe e não aponta para este repositório; remova-o antes"
  else
    mkdir -p "$(dirname "$GNOME_DIR")"
    ln -s "$HERE/extension" "$GNOME_DIR"
    echo "gnome: extensão instalada em $GNOME_DIR"
  fi
  if have gnome-extensions && gnome-extensions enable "$GNOME_UUID" 2>/dev/null; then
    echo "gnome: extensão ativada"
  else
    echo "gnome: depois de sair e entrar na sessão, rode: gnome-extensions enable $GNOME_UUID"
  fi
  echo "gnome: no Wayland, saia e entre na sessão para o GNOME Shell carregar a extensão"
}

gnome_uninstall() {
  if have gnome-extensions; then gnome-extensions disable "$GNOME_UUID" 2>/dev/null || true; fi
  if [ -L "$GNOME_DIR" ] && [ "$(readlink "$GNOME_DIR")" = "$HERE/extension" ]; then
    rm -f "$GNOME_DIR"
    echo "gnome: extensão removida de $GNOME_DIR"
  elif [ -e "$GNOME_DIR" ]; then
    echo "gnome: $GNOME_DIR não aponta para este repositório; não foi removido"
  fi
}

waybar_install() {
  install -m 755 "$HERE/waybar/claude-status-waybar.sh" "$WAYBAR_MODULE"
  echo "waybar: módulo instalado em $WAYBAR_MODULE"
  echo "waybar: cole $HERE/waybar/config.jsonc na config do waybar (e \"custom/claude\" em modules-right)"
  echo "waybar: cole $HERE/waybar/style.css no style.css e recarregue o waybar"
  have inotifywait || echo "waybar: dica: instale inotify-tools para atualizar na hora (sem ele, a cada 5 s)"
}

waybar_uninstall() {
  rm -f "$WAYBAR_MODULE"
  echo "waybar: módulo removido; tire o bloco \"custom/claude\" da config do waybar"
}

# Pasta de plugins: --plugin-dir, a do SwiftBar (preferência do app) ou a padrão do xbar.
macos_dir() {
  local dir="$plugin_dir"
  if [ -z "$dir" ] && have defaults; then
    dir="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
  fi
  if [ -z "$dir" ] && [ -d "$HOME/Library/Application Support/xbar/plugins" ]; then
    dir="$HOME/Library/Application Support/xbar/plugins"
  fi
  [ -n "$dir" ] || die "macos: pasta de plugins do SwiftBar/xbar não encontrada; abra o app uma vez ou use --plugin-dir DIR"
  printf '%s\n' "${dir/#\~/$HOME}"
}

macos_install() {
  local dir
  dir="$(macos_dir)"
  mkdir -p "$dir"
  install -m 755 "$HERE/macos/$MACOS_PLUGIN" "$dir/$MACOS_PLUGIN"
  echo "macos: plugin instalado em $dir/$MACOS_PLUGIN (renomeie o '5s' para mudar o intervalo)"
}

macos_uninstall() {
  local dir f
  dir="$(macos_dir)"
  for f in "$dir"/claude-status.*.sh; do
    [ -f "$f" ] && grep -q "$MACOS_MARK" "$f" && rm -f "$f" && echo "macos: plugin removido ($f)"
  done
  return 0
}

kde_install() {
  have kpackagetool6 || die "kde: kpackagetool6 não encontrado (vem com o Plasma 6)"
  if kpackagetool6 -t Plasma/Applet -s "$KDE_ID" >/dev/null 2>&1; then
    kpackagetool6 -t Plasma/Applet -u "$HERE/kde/$KDE_ID" >/dev/null
    echo "kde: plasmoid atualizado (pode ser preciso reiniciar o plasmashell)"
  else
    kpackagetool6 -t Plasma/Applet -i "$HERE/kde/$KDE_ID" >/dev/null
    echo "kde: plasmoid instalado; adicione 'Claude Status Monitor' pelo menu Adicionar widgets"
  fi
}

kde_uninstall() {
  if have kpackagetool6 && kpackagetool6 -t Plasma/Applet -r "$KDE_ID" >/dev/null 2>&1; then
    echo "kde: plasmoid removido"
  fi
  return 0
}

# ---------------------------------------------------------------- execução

if [ "$mode" = "install" ]; then
  mkdir -p "$BIN_DIR"
  install -m 755 "$HERE/bridge/claude-status-bridge.sh" "$BRIDGE"
  install -m 755 "$HERE/bridge/claude-status-summary.sh" "$SUMMARY"
  echo "ponte instalada em $BRIDGE (resumidor: $SUMMARY)"
  update_settings
  for t in ${targets[@]+"${targets[@]}"}; do "${t}_install"; done
else
  for t in ${targets[@]+"${targets[@]}"}; do "${t}_uninstall"; done
  rm -f "$BRIDGE" "$SUMMARY"
  echo "ponte e resumidor removidos de $BIN_DIR"
  update_settings
fi
