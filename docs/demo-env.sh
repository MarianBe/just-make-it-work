# Sandbox for recording docs/demo.tape with vhs.
# Sources into the tape's shell: fake HOME + a stubbed `opencode models`,
# so the recording shows the real installer UI without touching real config.
DEMO_TMP="/tmp/jmiw-demo"
rm -rf "$DEMO_TMP"
export HOME="$DEMO_TMP/home"
unset XDG_CONFIG_HOME
mkdir -p "$HOME/.local/bin" "$DEMO_TMP/bin"
# pre-add ~/.local/bin so the installer's PATH note doesn't clutter the demo
export PATH="$HOME/.local/bin:$PATH"

cat >"$DEMO_TMP/bin/opencode" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = "models" ] && cat <<'M'
opencode/big-pickle
opencode/deepseek-v4-flash-free
opencode/nemotron-3-ultra-free
github-copilot/claude-haiku-4.5
github-copilot/claude-opus-4.7
github-copilot/claude-opus-4.8
github-copilot/claude-opus-4.8-fast
github-copilot/claude-sonnet-4.6
github-copilot/claude-sonnet-5
github-copilot/gemini-3.1-pro-preview
github-copilot/gpt-5-mini
github-copilot/gpt-5.5
github-models/openai/gpt-4.1
github-models/meta/llama-4-scout-17b-16e-instruct
github-models/xai/grok-3
M
EOF
chmod +x "$DEMO_TMP/bin/opencode"
export PATH="$DEMO_TMP/bin:$PATH"
