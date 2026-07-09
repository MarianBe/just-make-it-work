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

# --- pick models per agent -----------------------------------------------------
# Detects available models via 'opencode models' (works for any provider,
# e.g. github-copilot/claude-opus-41), suggests a default per role, and asks
# on the terminal. Non-interactive (no tty) uses the detected defaults.
# Override without prompts: JMIW_ORCHESTRATOR_MODEL / JMIW_WORKER_MODEL /
# JMIW_SETUP_MODEL.
MODELS_FILE="$(mktemp)"
if command -v opencode >/dev/null 2>&1; then
  opencode models >"$MODELS_FILE" 2>/dev/null || true
fi

pick_default() {
  # first available model matching the preference patterns, in order
  local pat m
  for pat in "$@"; do
    m="$(grep -iE -- "$pat" "$MODELS_FILE" | head -1)" || true
    if [ -n "$m" ]; then
      echo "$m"
      return 0
    fi
  done
  return 1
}

ORCH_MODEL="${JMIW_ORCHESTRATOR_MODEL:-$(pick_default 'opus' 'sonnet' || echo 'anthropic/claude-opus-4-8')}"
WORKER_MODEL="${JMIW_WORKER_MODEL:-$(pick_default 'sonnet' 'opus' || echo 'anthropic/claude-sonnet-5')}"
SETUP_MODEL="${JMIW_SETUP_MODEL:-$(pick_default 'haiku' 'mini|nano|flash|lite' 'sonnet' || echo 'anthropic/claude-haiku-4-5')}"

TTY=""
# -r/-w on /dev/tty isn't enough: without a controlling terminal the open
# itself fails ("Device not configured"), so probe with a real open.
if [ -s "$MODELS_FILE" ] &&
  [ -z "${JMIW_ORCHESTRATOR_MODEL:-}${JMIW_WORKER_MODEL:-}${JMIW_SETUP_MODEL:-}" ] &&
  { true </dev/tty; } 2>/dev/null && { true >/dev/tty; } 2>/dev/null; then
  TTY=1
fi

# --- pure-bash arrow-key menu (no third-party dependencies) -------------------
menu_select() {
  # $1 header, $2 item to preselect (may be empty); menu items on stdin.
  # Echoes the selection; returns 1 on esc/q. Renders on /dev/tty.
  # Keys: up/down or j/k to move, enter to select, esc or q to cancel.
  local header="$1" pre="${2:-}"
  local items=() count=0 sel=0 top=0 vis=12 height drawn=0 i line key rest
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    items[count]="$line"
    [ "$line" = "$pre" ] && sel=$count
    count=$((count + 1))
  done
  [ "$count" -gt 0 ] || return 1
  [ "$count" -lt "$vis" ] && vis=$count
  height=$((vis + 1))
  [ "$count" -gt "$vis" ] && height=$((height + 1))

  printf '\033[?25l' >/dev/tty
  while true; do
    # keep the selection inside the viewport
    [ "$sel" -lt "$top" ] && top=$sel
    [ "$sel" -ge "$((top + vis))" ] && top=$((sel - vis + 1))
    {
      [ "$drawn" -eq 1 ] && printf '\033[%dA' "$height"
      printf '\r\033[K%s\n' "$header"
      for ((i = top; i < top + vis; i++)); do
        if [ "$i" -eq "$sel" ]; then
          printf '\r\033[K\033[7m> %s\033[0m\n' "${items[i]}"
        else
          printf '\r\033[K  %s\n' "${items[i]}"
        fi
      done
      [ "$count" -gt "$vis" ] && printf '\r\033[K  … %d/%d\n' "$((sel + 1))" "$count"
    } >/dev/tty
    drawn=1

    IFS= read -rsn1 key </dev/tty || key="q"
    case "$key" in
      $'\x1b')
        rest=""
        IFS= read -rsn2 -t 1 rest </dev/tty || true
        case "$rest" in
          '[A' | 'OA') sel=$(((sel + count - 1) % count)) ;;
          '[B' | 'OB') sel=$(((sel + 1) % count)) ;;
          '') # bare escape = cancel
            printf '\033[%dA\033[J\033[?25h' "$height" >/dev/tty
            return 1
            ;;
        esac
        ;;
      '') # enter
        printf '\033[%dA\033[J\033[?25h' "$height" >/dev/tty
        echo "${items[sel]}"
        return 0
        ;;
      k) sel=$(((sel + count - 1) % count)) ;;
      j) sel=$(((sel + 1) % count)) ;;
      q)
        printf '\033[%dA\033[J\033[?25h' "$height" >/dev/tty
        return 1
        ;;
    esac
  done
}

choose_model() {
  # $1 role label, $2 detected default; echoes the chosen provider/model id.
  # Nested: pick a provider, then one of its models. Esc at model level goes
  # back to providers; esc at provider level keeps the default.
  local role="$1" def="$2" prov model
  if [ -z "$TTY" ]; then
    echo "$def"
    return
  fi
  while true; do
    prov="$(cut -d/ -f1 "$MODELS_FILE" | sort -u | menu_select \
      "$role — pick provider (enter = show models, esc = keep $def)" "${def%%/*}")" ||
      {
        echo "$def"
        return
      }
    model="$(grep "^${prov}/" "$MODELS_FILE" | menu_select \
      "$role · $prov — pick model (esc = back to providers)" "$def")" &&
      {
        echo "$model"
        return
      }
  done
}

role_intro() {
  # $1 title, $2 description, $3 recommendation, $4 suggested model
  [ -z "$TTY" ] && return 0
  {
    printf '\n\033[1;36m%s\033[0m\n' "$1"
    printf '  %s\n' "$2"
    printf '  Recommended: %s\n' "$3"
    printf '  \033[2mSuggested default: %s\033[0m\n\n' "$4"
  } >/dev/tty
}

role_picked() {
  # $1 role, $2 chosen model
  [ -z "$TTY" ] && return 0
  printf '  \033[32m✓\033[0m %s → \033[1m%s\033[0m\n' "$1" "$2" >/dev/tty
}

if [ -n "$TTY" ]; then
  {
    printf '\n\033[1mModel selection\033[0m — three agents, three models.\n'
    printf '\033[2mArrows/j/k move · enter selects · esc keeps the suggested default.\033[0m\n'
  } >/dev/tty
fi

role_intro "Orchestrator" \
  "Your main agent. Fetches the ticket, plans the work, and oversees everything — it delegates all implementation and never edits files itself." \
  "a powerful reasoning model (Opus class)" "$ORCH_MODEL"
ORCH_MODEL="$(choose_model "orchestrator" "$ORCH_MODEL")"
role_picked "orchestrator" "$ORCH_MODEL"

role_intro "Worker" \
  "Does the actual implementation: writes code, edits files, runs tests. Gets one well-scoped task at a time from the orchestrator." \
  "a strong, fast coding model (Sonnet class)" "$WORKER_MODEL"
WORKER_MODEL="$(choose_model "worker" "$WORKER_MODEL")"
role_picked "worker" "$WORKER_MODEL"

role_intro "Setup" \
  "Bootstraps fresh worktrees by following your repo's .opencode/setup.md (install deps, copy env files). Simple, literal work." \
  "the cheapest model you have (Haiku/mini class)" "$SETUP_MODEL"
SETUP_MODEL="$(choose_model "setup" "$SETUP_MODEL")"
role_picked "setup" "$SETUP_MODEL"

rm -f "$MODELS_FILE"

set_model() {
  # $1 agent file, $2 model id
  local tmp
  tmp="$(mktemp)"
  sed "s|^model: .*|model: $2|" "$1" >"$tmp" && mv "$tmp" "$1"
}
set_model "$CONFIG_DIR/agents/orchestrator.md" "$ORCH_MODEL"
set_model "$CONFIG_DIR/agents/worker.md" "$WORKER_MODEL"
set_model "$CONFIG_DIR/agents/setup.md" "$SETUP_MODEL"

echo "models: orchestrator=$ORCH_MODEL worker=$WORKER_MODEL setup=$SETUP_MODEL"
echo "  (change later: edit 'model:' in $CONFIG_DIR/agents/*.md)"

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
