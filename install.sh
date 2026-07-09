#!/usr/bin/env bash
#
# just-make-it-work installer
#
#   curl -fsSL https://raw.githubusercontent.com/MarianBe/just-make-it-work/main/install.sh | bash
#
# Installs:
#   ~/.config/opencode/agents/orchestrator.md   opus orchestrator (primary agent)
#   ~/.config/opencode/agents/worker.md         sonnet worker (subagent)
#   ~/.config/opencode/agents/setup.md          haiku worktree bootstrapper (subagent)
#   ~/.config/opencode/commands/ticket.md       /ticket command
#   ~/.local/bin/ticket                         worktree wrapper CLI
# and merges Linear + Jira MCP servers into ~/.config/opencode/opencode.json.
#
set -euo pipefail

REPO_URL="${JMIW_REPO_URL:-https://github.com/MarianBe/just-make-it-work}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
BIN_DIR="$HOME/.local/bin"

# --- locate source (local checkout, or clone when piped through curl) -------
SRC=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/bin/ticket" ]; then
  SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  command -v git >/dev/null 2>&1 || {
    echo "git is required" >&2
    exit 1
  }
  SRC="$(mktemp -d)"
  trap 'rm -rf "$SRC"' EXIT
  echo "cloning ${REPO_URL} ..."
  git clone --quiet --depth 1 "$REPO_URL" "$SRC"
fi

# --- agents, commands, CLI ---------------------------------------------------
mkdir -p "$CONFIG_DIR/agents" "$CONFIG_DIR/commands" "$BIN_DIR"
cp "$SRC/opencode/agents/orchestrator.md" "$CONFIG_DIR/agents/orchestrator.md"
cp "$SRC/opencode/agents/worker.md" "$CONFIG_DIR/agents/worker.md"
cp "$SRC/opencode/agents/setup.md" "$CONFIG_DIR/agents/setup.md"
cp "$SRC/opencode/commands/ticket.md" "$CONFIG_DIR/commands/ticket.md"
install -m 755 "$SRC/bin/ticket" "$BIN_DIR/ticket"
echo "installed agents, /ticket command, and 'ticket' CLI"

# --- merge MCP servers into opencode.json ------------------------------------
MCP_SNIPPET='{
  "linear": { "type": "remote", "url": "https://mcp.linear.app/mcp", "enabled": true },
  "jira":   { "type": "remote", "url": "https://mcp.atlassian.com/v1/sse", "enabled": true }
}'

if command -v python3 >/dev/null 2>&1; then
  if OC_CONFIG="$CONFIG_DIR/opencode.json" python3 - <<'PY'; then
import json, os, sys

path = os.environ["OC_CONFIG"]
cfg = {}
if os.path.exists(path):
    with open(path) as f:
        try:
            cfg = json.load(f)
        except ValueError:
            sys.exit(1)  # jsonc/comments or invalid json -> manual step

cfg.setdefault("$schema", "https://opencode.ai/config.json")
mcp = cfg.setdefault("mcp", {})
mcp.setdefault("linear", {"type": "remote", "url": "https://mcp.linear.app/mcp", "enabled": True})
mcp.setdefault("jira", {"type": "remote", "url": "https://mcp.atlassian.com/v1/sse", "enabled": True})

with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PY
    echo "merged Linear + Jira MCP servers into $CONFIG_DIR/opencode.json"
  else
    echo "could not auto-edit $CONFIG_DIR/opencode.json (comments or invalid JSON?)."
    echo "add this to its \"mcp\" section manually:"
    echo "$MCP_SNIPPET"
  fi
else
  echo "python3 not found; add this to the \"mcp\" section of $CONFIG_DIR/opencode.json manually:"
  echo "$MCP_SNIPPET"
fi

# --- PATH check ---------------------------------------------------------------
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo
    echo "NOTE: $BIN_DIR is not in your PATH. Add to your shell profile:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    ;;
esac

cat <<'EOF'

done. next steps:

  1. authenticate the trackers (one-time, opens browser):
       opencode mcp auth linear
       opencode mcp auth jira

  2. work a ticket in its own worktree:
       cd <your-repo>
       ticket ABC-123

  3. parallel tickets: run 'ticket XYZ-456' in another terminal/tmux pane.

  cleanup when merged:  ticket cleanup ABC-123
EOF
