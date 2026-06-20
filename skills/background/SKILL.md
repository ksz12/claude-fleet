---
name: background
description: Launch a prompt into a tracked, interactive background Claude session in tmux. Use when the user says "/background <prompt>", "run this in the background", "spin up a session for X", or wants work done in a separate supervised session. Expands the prompt, names + scaffolds a repo, and launches an interactive (not -p) session the user can attach to and redirect.
---

# /background — launch a tracked interactive background session

You are launching a **new interactive Claude session** in tmux that the fleet
harness will track. Work through these steps in order. Helper scripts live in
`~/.claude/fleet/bin/`.

## 0. Parse the request
From the user's input, extract:
- the **prompt** (the task for the new session)
- `--repo <name>` — explicit repo to use (optional)
- `--task <t-NNN>` — taskboard id to claim on launch (optional)
- `--yolo` — skip the confirmation step (optional)

## 1. Load preferences
If a `style-guide` memory exists — `~/.claude/memory/global/style-guide.md` (via
the companion [grimoire](https://github.com/ksz12/grimoire) memory layer) or a
`style-guide` entry in a `MEMORY.md` — read it and apply it to the expanded
prompt. Also skim available `feedback`/`user` memories. If none exist, proceed
without a style guide.

## 2. Expand the prompt — be critical
Rewrite the user's prompt into a **comprehensive, self-contained brief** for a
fresh session that has none of this conversation's context. You MUST:
- State the goal and concrete deliverables.
- Apply the user's style guide / preferences.
- **Critically add what's likely missing**: edge cases, testing/verification
  expectations, constraints, "definition of done". Call out assumptions.
- Keep it actionable, not padded.
Write the expanded prompt to a temp file: `$CLAUDE_JOB_DIR/tmp/bg-prompt.txt`
(or `/tmp` if that's unset).

## 3. Name the session
A short, **lowercase, <=40 char**, descriptive slug (e.g. `auth-rate-limiter`).
Use `~/.claude/fleet/bin/fleet-lib.sh`'s convention if unsure.

## 4. Resolve the repo
- If `--repo` given: use `~/claude-sessions/<repo>` (or the explicit path).
- Else **scan for a match**: list existing names in `~/.claude/fleet/sessions/`,
  `~/.claude/fleet/archive/`, and `~/claude-sessions/`. If one clearly matches
  the task's topic, **propose reusing it and confirm with the user** (never
  auto-reuse on a fuzzy match — reuse is destructive).
- Else create a **new** repo at `~/claude-sessions/<name>/`.

### Same-repo isolation
If you're reusing a repo that **already has a live session** (check
`~/.claude/fleet/sessions/` for an entry whose `repo_root` matches), do NOT
share the working tree. Create a git worktree instead:
`git -C <repo> worktree add ~/claude-sessions/<name> -b <name>` and launch in
that worktree. Sessions then share committed history, not live files.

## 5. Scaffold the repo
In the chosen dir: `git init` if not already a repo; write a **README.md** and
**CLAUDE.md** describing what this session is for (goal, deliverables, key
decisions from the expanded prompt). Create `.fleet/` for the mailbox.

## 6. Confirm (unless --yolo)
Show the user: the chosen **name**, **repo path**, and the **expanded prompt**.
Ask for approval or edits. Apply edits to the temp file. Skip this step only if
`--yolo` was passed.

## 7. Launch
Call the launcher (it handles cd, name-injection, the `>`-prompt wait,
load-buffer/paste-buffer — never use send-keys for the prompt yourself — and,
on macOS, auto-opens a new Terminal.app window attached to the session so the
user can alt-tab to it; set `FLEET_NO_WINDOW=1` to suppress that in
headless/cron contexts):
```
~/.claude/fleet/bin/fleet-launch --name <name> --repo <repo-path> \
    --prompt-file <temp-prompt-file> [--task <t-NNN>]
```
If `--task` was given, also run `fleet-task claim <t-NNN> --session <name>`.

## 8. Report
Tell the user the session name, that a new Terminal window was opened attached
to it (and how to re-attach manually: `tmux attach -t <name>`), and that it'll
appear on `claude-dashboard`. If the launcher warned that readiness wasn't
confirmed, tell them to check the pane.
