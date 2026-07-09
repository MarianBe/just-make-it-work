# just-make-it-work

Give [opencode](https://opencode.ai) a Linear or Jira ticket id. An **Opus
orchestrator** fetches the ticket, writes a plan, and delegates the
implementation to **Sonnet worker subagents** — inside a dedicated **git
worktree per ticket**, so you can run several tickets in parallel.

## Install (one command)

```sh
curl -fsSL https://raw.githubusercontent.com/MarianBe/just-make-it-work/main/install.sh | bash
```

Then authenticate the trackers once (opens your browser):

```sh
opencode mcp auth linear
opencode mcp auth jira
```

That's it. The installer puts:

| What | Where |
|---|---|
| `orchestrator` primary agent (Opus, can't edit files) | `~/.config/opencode/agents/orchestrator.md` |
| `worker` subagent (Sonnet, does the implementation) | `~/.config/opencode/agents/worker.md` |
| `setup` subagent (Haiku, bootstraps fresh worktrees) | `~/.config/opencode/agents/setup.md` |
| `/ticket` command | `~/.config/opencode/commands/ticket.md` |
| `ticket` wrapper CLI | `~/.local/bin/ticket` |
| Linear + Jira remote MCP servers | merged into `~/.config/opencode/opencode.json` |

## Usage

```sh
cd ~/code/my-app
ticket ABC-123
```

This:

1. Creates a git worktree at `../my-app-ABC-123` on branch `ticket/ABC-123`
   (based on your default branch; pass a second arg to override:
   `ticket ABC-123 develop`).
2. Bootstraps the worktree: if your repo has a `.opencode/setup.md`, a cheap
   Haiku `setup` agent reads it and executes the steps (see below).
3. Launches the opencode TUI in that worktree with the orchestrator agent and
   the ticket already queued.

The orchestrator then: fetches the ticket (tries Linear, falls back to Jira) →
explores the code → shows you a plan → dispatches self-contained tasks to the
Sonnet `worker` subagent (parallel where independent) → reviews diffs, runs
tests → commits on `ticket/ABC-123`. It never edits files itself — write/edit
tools are disabled on the orchestrator, so all implementation goes through
workers.

### Worktree setup: `.opencode/setup.md`

A fresh worktree is a full checkout of tracked files, but gitignored things
(`node_modules`, `.env`, generated code) are missing. Describe how to fix that
in plain language in `.opencode/setup.md`, committed to your repo:

```markdown
# Worktree setup

- Copy `.env` and `.env.local` from the main checkout (they're gitignored).
- Run `pnpm install --frozen-lockfile`.
- Run `pnpm db:generate`.
```

On every fresh worktree, `ticket` runs the Haiku-powered `setup` agent
non-interactively against this file before opening the TUI. It executes the
steps literally, knows the main checkout is the first entry of
`git worktree list`, retries the obvious way once on failure, and reports —
it never touches application code and never commits. No file → step is
skipped. The orchestrator also dispatches `setup` itself if it lands in an
unbootstrapped worktree (e.g. desktop-app worktree flow).

### Parallel tickets

Each ticket lives in its own worktree + branch + opencode session. Open another
terminal (or tmux pane):

```sh
ticket XYZ-456
```

Nothing collides — separate directories, separate branches.

### Picking work back up / giving feedback

When the worktree already exists, `ticket` continues the ticket's last
opencode session (full conversation context intact) instead of starting
over:

```sh
ticket ABC-123                                 # reopen last session
ticket ABC-123 the modal still flickers on iOS # reopen + send feedback
ticket continue ABC-123                        # explicit form (alias: resume)
ticket continue ABC-123 address the PR review comments
```

opencode scopes its session list to the current worktree directory, so each
ticket resumes its own session even with many tickets in flight. Note: when
the worktree exists, extra arguments are feedback, not a base branch — the
base only matters at creation time.

### Housekeeping

```sh
ticket list                    # worktrees for this repo
ticket cleanup ABC-123         # remove worktree after merging (keeps branch)
ticket cleanup ABC-123 --force # discard uncommitted changes too
```

Existing `ticket/ABC-123` branches are reused when the worktree is recreated.

### Without the wrapper

Inside any opencode session you can also run the command directly:

```
/ticket ABC-123
```

In the **desktop app**, create a new session, pick "worktree" in the
new-session view, then run `/ticket ABC-123` — same result as the CLI wrapper.

## Models

The installer runs `opencode models`, suggests a model per role from whatever
providers you actually have (works with GitHub Copilot, Anthropic, etc. —
e.g. `github-copilot/claude-opus-4.8`), and asks you to confirm. Preference
per role: orchestrator opus→sonnet, worker sonnet→opus, setup
haiku→mini/nano/flash/lite→sonnet.

Selection uses a built-in arrow-key picker (pure bash, no dependencies),
nested by provider so long model lists stay manageable: pick the provider
first, then one of its models. Arrow keys or j/k move, Enter selects, Esc at
the model level goes back to providers, Esc at the provider level keeps the
suggested default — so pressing Esc three times accepts all suggestions. The
suggested provider/model is preselected at each level.

Non-interactive installs (no tty) take the detected defaults. Skip the
prompts entirely with env vars:

```sh
JMIW_ORCHESTRATOR_MODEL=github-copilot/claude-opus-41 \
JMIW_WORKER_MODEL=github-copilot/claude-sonnet-45 \
JMIW_SETUP_MODEL=github-copilot/claude-haiku-45 \
  bash install.sh
```

Change later by editing the `model:` line in `~/.config/opencode/agents/*.md`,
or override per-agent in `opencode.json`:

```json
{
  "agent": {
    "worker": { "model": "github-copilot/claude-sonnet-45" }
  }
}
```

If `opencode` isn't installed yet when you run the installer, the files keep
the Anthropic defaults (`anthropic/claude-opus-4-8`, `anthropic/claude-sonnet-5`,
`anthropic/claude-haiku-4-5`) — rerun the installer after setting up opencode,
or edit the agent files.

## Jira note

The installer registers Atlassian's remote MCP (`https://mcp.atlassian.com/v1/sse`).
If your org runs Jira Data Center / self-hosted, replace the `jira` entry in
`~/.config/opencode/opencode.json` with your own MCP server.

## Uninstall

```sh
rm ~/.config/opencode/agents/{orchestrator,worker,setup}.md \
   ~/.config/opencode/commands/ticket.md \
   ~/.local/bin/ticket
```

and remove the `linear` / `jira` entries from `~/.config/opencode/opencode.json`.
