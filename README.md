# claude-fleet

**A tmux-based supervisor for running many interactive Claude Code sessions in
parallel** — each one independently attachable and steerable, with a live
dashboard, a shared taskboard, an inter-session mailbox, and a liveness watchdog.
Built on plain tmux + Claude Code hooks (no experimental dependencies), composed
from `bash` + `python3` + `jq`.

> **Status / scope.** Built for one person's setup and shared in case it's useful.
> macOS-first (the launcher auto-opens a Terminal window via `osascript`; set
> `FLEET_NO_WINDOW=1` to skip it — the rest is portable). Licensed MIT.
> Companion project: **[grimoire](https://github.com/ksz12/grimoire)**, a memory
> layer that `/conclude` integrates with when present (optional).

## What it gives you

- **`/background <prompt>`** — expand a terse prompt into a self-contained brief,
  scaffold a repo, and launch a *tracked, interactive* Claude session in tmux you
  can attach to and redirect (not a fire-and-forget `-p` run).
- **`/taskboard`** — a shared task list across sessions (`t-001` ids; add, claim,
  complete), backed by `fleet-task`.
- **`/conclude`** — end a session cleanly: a critical retrospective (token burn,
  re-prompting, repeated mistakes), capture durable learnings, then tear down
  (archive state, remove worktree, kill tmux).
- **`claude-dashboard`** — a live, read-only view of every session's status.
- **`fleet-watchdog`** — liveness/escalation for stuck or dead sessions.
- **`fleet-send`** — an inter-session mailbox (`.fleet/`) for messaging peers.

## Architecture

```
tmux session "fleet"
  ├─ claude-dashboard            (read-only live view of all sessions)
  └─ session <name> × N          (interactive `claude` TUIs, each its own repo)

~/.claude/fleet/
  ├─ sessions/<name>.json        per-session state (status, repo, transcript)
  ├─ archive/                    concluded sessions
  ├─ tasks/tasks.json            the shared taskboard (+ .lock)
  └─ index.json                  cwd → session-name map
~/claude-sessions/<name>/        the session's working repo (+ .fleet/ mailbox)
```

Identity: the session **name** is the primary key, injected as `FLEET_SESSION_NAME`
at launch; `fleet-hook.sh` (wired into Claude Code's lifecycle hooks) keeps each
session's JSON current on SessionStart / UserPromptSubmit / PreToolUse / Stop /
SessionEnd. See [PLAN.md](PLAN.md) for the full design rationale.

## Requirements

`tmux`, `bash`, `python3`, `jq`, `git`. macOS for the auto-Terminal-window only
(optional). Claude Code with hooks support.

## Install

```sh
./test.sh        # smoke-check: every script parses
./install.sh     # install bin + skills, wire fleet-hook into settings.json
./install.sh --uninstall
```

`install.sh` is idempotent and adds its hooks *alongside* any existing ones
(it never overwrites your hook config).

## Using it day-to-day

Each `/background` launch is its **own** tmux session named after the job, so the
sessions sit alongside your `main` session as siblings — attach to whichever you
want; they keep running after you detach.

### Attach, detach, switch

```sh
tmux ls                          # list every session
tmux attach -t blinds-store      # attach to one
#   Ctrl-b d   detach (it keeps running)
#   Ctrl-b s   interactive session switcher
#   Ctrl-b ( ) previous / next session
```

### One OS window per session (what the launcher does on macOS)

`fleet-launch` auto-opens a Terminal window attached to each new session
(set `FLEET_NO_WINDOW=1` to skip). Re-open one manually any time:

```sh
osascript -e 'tell application "Terminal" to do script "tmux attach -t blinds-store"'
```

### "Mission control" — dashboard + sessions in split panes

Tile the live dashboard and a couple of running sessions in a single window:

```sh
tmux new-session -d -s fleetview -n control 'claude-dashboard'
tmux split-window  -h -t fleetview 'tmux attach -t blinds-store'
tmux split-window  -v -t fleetview 'tmux attach -t discord-traitors'
tmux select-layout -t fleetview tiled
tmux attach        -t fleetview
```

Attaching a session *inside a pane* shares that session's view (tmux clamps it to
the smallest attached client). For independent sizing, prefer one OS window per
session (above) and keep the split-pane window just for the read-only dashboard.

### Pane keys (default prefix `Ctrl-b`)

```
Ctrl-b "      split top / bottom        Ctrl-b z      zoom / unzoom a pane
Ctrl-b %      split left / right        Ctrl-b ←↑↓→   move between panes
Ctrl-b x      kill the pane             Ctrl-b d      detach (session keeps running)
```

## Layout

```
bin/
  fleet-hook.sh            lifecycle dispatcher (wired into Claude Code hooks)
  fleet-launch            scaffold + launch a tracked tmux session
  fleet-task              taskboard CRUD (python)
  fleet-send              inter-session mailbox
  fleet-resolve-transcript  map a session to its transcript + usage (python)
  fleet-watchdog          liveness/escalation (python)
  claude-dashboard        live status view (python)
  fleet-up / fleet-lib.sh  bring-up helper + shared shell lib
skills/{background,taskboard,conclude}/SKILL.md
PLAN.md                   design rationale
```
