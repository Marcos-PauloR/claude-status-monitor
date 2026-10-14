#!/usr/bin/env bash
# <xbar.title>Claude Status Monitor</xbar.title>
# <xbar.version>v1.1</xbar.version>
# <xbar.author>Marcos Paulo R</xbar.author>
# <xbar.desc>Context and plan usage of your Claude Code sessions (session, weekly, ctx per window).</xbar.desc>
# <xbar.dependencies>bash,jq</xbar.dependencies>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
#
# Claude Status Monitor — plugin SwiftBar/xbar para a barra de menus do macOS.
# O "5s" do nome é o intervalo de atualização. Argumentos extras vão para o resumidor
# (ex.: renomear para claude-status.5s.sh e editar ARGS abaixo: --warn 60 --crit 85).

ARGS=()

# SwiftBar e xbar rodam os plugins com um PATH mínimo: sem isso o jq do Homebrew não é achado.
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

SUMMARY="${CLAUDE_STATUS_SUMMARY:-$(command -v claude-status-summary.sh)}"

if [ -z "$SUMMARY" ] || ! command -v jq >/dev/null; then
  echo "✳ Claude ?"
  echo "---"
  [ -z "$SUMMARY" ] && echo "claude-status-summary.sh not found — run ./install.sh"
  command -v jq >/dev/null || echo "jq not found — brew install jq | href=https://jqlang.org/download/"
  exit 0
fi

"$SUMMARY" --format swiftbar ${ARGS[@]+"${ARGS[@]}"} || { echo "✳ Claude ?"; echo "---"; echo "claude-status-summary.sh failed"; }
