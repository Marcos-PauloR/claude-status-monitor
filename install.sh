#!/usr/bin/env bash
# Claude Status Monitor — instalador.
#
# Uso: ./install.sh [--target ALVO]... [opções]      instala/atualiza (idempotente)
#      ./install.sh --update [opções]                baixa a versão nova (git pull) e reinstala
#                                                    os alvos já instalados
#      ./install.sh --uninstall [--target ALVO]...   remove (o config é mantido)
#
# Opções (gravadas em ~/.config/claude-status/config, que também pode ser editado):
#   --warn N      % a partir do qual fica amarelo (padrão 70)
#   --crit N      % a partir do qual fica vermelho (padrão 90)
#   --inactive N  minutos sem atualização até esconder a janela (padrão 15)
#   --lang L      idioma: auto (do sistema), en ou pt
#   --plugin-dir  pasta de plugins do SwiftBar/xbar (alvo macos)
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
#
# Os alvos instalados ficam em targets= no config; o --update usa essa lista (ou, em
# instalações anteriores à v1.2, detecta o que está instalado). Só o --update usa a rede.
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
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/claude-status/config"

die() { printf 'erro: %s\n' "$1" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Ajuda = comentário do topo do arquivo (até a primeira linha que não é comentário).
usage() { awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"; }

mode="install"
targets=()
plugin_dir=""
opt_warn="" opt_crit="" opt_inactive="" opt_lang=""
while [ $# -gt 0 ]; do
  case "$1" in
    --uninstall) mode="uninstall" ;;
    --update) mode="update" ;;
    --target)
      case "${2:-}" in
        gnome|waybar|macos|kde) targets+=("$2") ;;
        *) die "alvo inválido: '${2:-}' (use gnome, waybar, macos ou kde)" ;;
      esac
      shift ;;
    --plugin-dir) plugin_dir="${2:-}"; [ -n "$plugin_dir" ] || die "--plugin-dir precisa de um diretório"; shift ;;
    --warn) opt_warn="${2:-}"; shift ;;
    --crit) opt_crit="${2:-}"; shift ;;
    --inactive) opt_inactive="${2:-}"; shift ;;
    --lang) opt_lang="${2:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "opção desconhecida: $1 (veja --help)" ;;
  esac
  shift
done

have jq || die "jq não encontrado (Fedora: sudo dnf install jq · macOS: brew install jq · Debian/Ubuntu: sudo apt install jq)"

# ---------------------------------------------------------------- config único

# Valor atual de uma chave no config (vazio se não houver).
config_get() {
  [ -f "$CONFIG" ] || return 0
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\([^[:space:]]*\).*/\1/p" "$CONFIG" | tail -n 1
}
# Grava uma chave no config sem mexer no resto (comentários e edições à mão ficam).
config_set() {
  local tmp
  tmp="$(mktemp "$CONFIG.XXXXXX")"
  awk -v k="$1" -v v="$2" '
    $0 ~ "^[[:space:]]*" k "[[:space:]]*=" { if (!done) print k "=" v; done = 1; next }
    { print }
    END { if (!done) print k "=" v }
  ' "$CONFIG" > "$tmp"
  mv -f "$tmp" "$CONFIG"
}

# Lista de alvos "a,b" sem repetição, na ordem canônica.
targets_join() {
  local out="" t
  for t in gnome kde waybar macos; do
    case " $* " in *" $t "*) out="${out:+$out,}$t" ;; esac
  done
  printf '%s\n' "$out"
}
in_range() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; [ "$1" -ge "$2" ] && [ "$1" -le "$3" ]; }

# Valida tudo antes de alterar qualquer coisa: flags vencem o config, que vence o padrão.
warn="${opt_warn:-$(config_get warn)}"; warn="${warn:-70}"
crit="${opt_crit:-$(config_get crit)}"; crit="${crit:-90}"
inactive="${opt_inactive:-$(config_get inactive)}"; inactive="${inactive:-15}"
lang="${opt_lang:-$(config_get lang)}"; lang="${lang:-auto}"
if [ "$mode" != "uninstall" ]; then
  in_range "$warn" 1 100 || die "--warn precisa ser um número de 1 a 100 (recebido: $warn)"
  in_range "$crit" 1 100 || die "--crit precisa ser um número de 1 a 100 (recebido: $crit)"
  in_range "$inactive" 1 1440 || die "--inactive precisa ser um número de 1 a 1440 (recebido: $inactive)"
  [ "$crit" -ge "$warn" ] || die "vermelho ($crit%) não pode ser menor que amarelo ($warn%)"
  case "$lang" in auto|en|pt) ;; *) die "--lang precisa ser auto, en ou pt (recebido: $lang)" ;; esac
fi

# Cria o config na primeira instalação; depois só grava as chaves das flags passadas,
# para não apagar o que a pessoa editou à mão. targets= acompanha os alvos instalados.
write_config() {
  local recorded new changed=""
  recorded="$(config_get targets | tr ',' ' ')"
  if [ "$mode" = "install" ]; then
    new="$(targets_join $recorded ${targets[@]+"${targets[@]}"})"
  else
    # Sem "case" dentro de $( ): o bash 3.2 (macOS) não entende o ")" do padrão ali.
    local keep="" t
    for t in $recorded; do
      case " ${targets[*]-} " in *" $t "*) ;; *) keep="$keep $t" ;; esac
    done
    new="$(targets_join $keep)"
  fi
  if [ ! -f "$CONFIG" ]; then
    [ "$mode" = "install" ] || return 0
    mkdir -p "$(dirname "$CONFIG")"
    cat > "$CONFIG" <<CONF
# Claude Status Monitor — configuração (pode editar; vale para statusline, waybar, macOS e KDE)
# warn: % para ficar amarelo · crit: % para ficar vermelho · inactive: minutos até esconder a janela
# lang: auto (idioma do sistema), en ou pt · targets: mostradores instalados (usado pelo --update)
warn=$warn
crit=$crit
inactive=$inactive
lang=$lang
targets=$new
CONF
    echo "config: $CONFIG (amarelo ${warn}%, vermelho ${crit}%, inativa após ${inactive} min, idioma $lang)"
    return 0
  fi
  if [ -n "$opt_warn" ]; then config_set warn "$warn"; changed=1; fi
  if [ -n "$opt_crit" ]; then config_set crit "$crit"; changed=1; fi
  if [ -n "$opt_inactive" ]; then config_set inactive "$inactive"; changed=1; fi
  if [ -n "$opt_lang" ]; then config_set lang "$lang"; changed=1; fi
  if [ "$new" != "$(targets_join $recorded)" ]; then
    config_set targets "$new"
  fi
  if [ -n "$changed" ]; then
    echo "config: $CONFIG (amarelo ${warn}%, vermelho ${crit}%, inativa após ${inactive} min, idioma $lang)"
  else
    echo "config: $CONFIG (sem alterações)"
  fi
}

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
  # Flags passadas também valem nas preferências do GNOME (GSettings).
  if have gsettings; then
    local gs=(gsettings --schemadir "$HERE/extension/schemas")
    local schema="org.gnome.shell.extensions.claude-status"
    if [ -n "$opt_warn" ]; then "${gs[@]}" set "$schema" warn-threshold "$warn"; fi
    if [ -n "$opt_crit" ]; then "${gs[@]}" set "$schema" crit-threshold "$crit"; fi
    if [ -n "$opt_inactive" ]; then "${gs[@]}" set "$schema" inactive-minutes "$inactive"; fi
    if [ -n "$opt_lang" ]; then "${gs[@]}" set "$schema" language "$lang"; fi
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

# ---------------------------------------------------------------- atualização

# Alvos já instalados, para instalações sem targets= (anteriores à v1.2).
detect_targets() {
  if [ -L "$GNOME_DIR" ] && [ "$(readlink "$GNOME_DIR")" = "$HERE/extension" ]; then echo gnome; fi
  if have kpackagetool6 && kpackagetool6 -t Plasma/Applet -s "$KDE_ID" >/dev/null 2>&1; then echo kde; fi
  if [ -e "$WAYBAR_MODULE" ]; then echo waybar; fi
  local dir f
  dir="$( (macos_dir) 2>/dev/null || true)"
  for f in "$dir"/claude-status.*.sh; do
    if [ -n "$dir" ] && [ -f "$f" ] && grep -q "$MACOS_MARK" "$f"; then echo macos; break; fi
  done
}

# git pull no repositório e roda o install.sh novo com os alvos já instalados (+ --target extras).
update() {
  have git || die "update: git não encontrado"
  git -C "$HERE" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "update: $HERE não é um clone do git; baixe a versão nova do GitHub e rode ./install.sh de novo"
  local old new list args=() t
  old="$(git -C "$HERE" rev-parse HEAD)"
  echo "update: buscando a versão nova (git pull)..."
  git -C "$HERE" pull --ff-only --quiet \
    || die "update: git pull falhou; nada foi reinstalado (mudanças locais? veja: git -C $HERE status)"
  new="$(git -C "$HERE" rev-parse HEAD)"
  if [ "$old" = "$new" ]; then
    echo "update: o código já estava na versão mais recente; reinstalando mesmo assim"
  else
    echo "update: novidades:"
    git -C "$HERE" log --oneline --no-decorate "$old..$new" | sed 's/^/  /'
  fi
  list="$(config_get targets | tr ',' ' ')"
  [ -n "$list" ] || list="$(detect_targets | tr '\n' ' ')"
  list="$(targets_join $list ${targets[@]+"${targets[@]}"} | tr ',' ' ')"
  for t in $list; do args+=(--target "$t"); done
  if [ -n "$opt_warn" ]; then args+=(--warn "$opt_warn"); fi
  if [ -n "$opt_crit" ]; then args+=(--crit "$opt_crit"); fi
  if [ -n "$opt_inactive" ]; then args+=(--inactive "$opt_inactive"); fi
  if [ -n "$opt_lang" ]; then args+=(--lang "$opt_lang"); fi
  if [ -n "$plugin_dir" ]; then args+=(--plugin-dir "$plugin_dir"); fi
  if [ -n "${list// /}" ]; then echo "update: reinstalando (alvos: ${list% })"
  else echo "update: reinstalando só a ponte (nenhum mostrador instalado foi encontrado)"; fi
  exec "$HERE/install.sh" ${args[@]+"${args[@]}"}
}

# ---------------------------------------------------------------- execução

if [ "$mode" = "update" ]; then
  update
elif [ "$mode" = "install" ]; then
  mkdir -p "$BIN_DIR"
  install -m 755 "$HERE/bridge/claude-status-bridge.sh" "$BRIDGE"
  install -m 755 "$HERE/bridge/claude-status-summary.sh" "$SUMMARY"
  echo "ponte instalada em $BRIDGE (resumidor: $SUMMARY)"
  write_config
  update_settings
  for t in ${targets[@]+"${targets[@]}"}; do "${t}_install"; done
else
  for t in ${targets[@]+"${targets[@]}"}; do "${t}_uninstall"; done
  rm -f "$BRIDGE" "$SUMMARY"
  echo "ponte e resumidor removidos de $BIN_DIR"
  update_settings
  write_config
  if [ -f "$CONFIG" ]; then echo "config mantido em $CONFIG (apague à mão se quiser)"; fi
fi
