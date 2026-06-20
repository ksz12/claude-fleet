# Claude Fleet — Plan

A tmux-based supervisor + dashboard over multiple **interactive, redirectable, independent** Claude Code sessions. Custom layers built on top of a plain tmux + hooks substrate.

## Scope recap (your answers)
- **Core deltas to build:** watchdog/auto-recovery + global cross-session dashboard.
- **Managed units:** multiple *interactive* Claude TUIs you can attach to and redirect; functionally independent; may share context.
- **Agent teams:** assessed — see verdict below.

## Agent-teams verdict (assess-fit result)
Agent teams already covers the *substrate* you described (multiple independent interactive instances, directly steerable, shared task list). But:
- The two things you actually want — **watchdog** and **global dashboard** — are exactly what it does **not** provide.
- Its experimental weaknesses (**session-resumption issues, task-status lag**) land *directly on the watchdog use case*.
- Its shared task list is **not externally scriptable** the way your `/taskboard` needs.

**Recommendation: do NOT use agent teams.** Build on plain tmux + hooks. You keep full external control (the thing a supervisor requires) and avoid betting durability on an experimental feature.

---

## Architecture

```
┌─ tmux session "fleet" ──────────────────────────────────┐
│  pane 0: claude-dashboard (renderer, read-only)         │
│  pane 1..N: interactive `claude --dangerously-skip-...` │
│             (attach & redirect any)                     │
└─────────────────────────────────────────────────────────┘
        ▲ reads state                 │ each session emits
        │                             ▼ lifecycle via HOOKS
   ~/.claude/fleet/                hooks → fleet-hook.sh dispatcher
     sessions/<name>.json   ← per-session state (no shared-write contention)
     tasks/tasks.json       ← taskboard (flock for id counter)
     tasks/seq              ← monotonic t-NNN counter
     archive/<name>.json    ← concluded/dead sessions
     alerts.log             ← watchdog escalations
     bin/                   ← scripts: fleet-hook.sh, claude-dashboard, fleet-watchdog
     index.json             ← cwd → name map (launcher writes; hook reads)
```

### Backbone: hooks + per-session state files
- Hooks installed **globally** in `~/.claude/settings.json` → every Claude session reports.
- One dispatcher `fleet-hook.sh <event>` reads stdin JSON (`session_id`, `cwd`, `transcript_path`) and atomically updates `sessions/<name>.json` (write-temp + rename).
- **Correlation = name injection (primary):** `/background` launches with `FLEET_SESSION_NAME=<name> claude …`; the hook reads `$FLEET_SESSION_NAME` → exact, per-process, works even when cwd is shared. Fallbacks: `cwd` lookup in `index.json`, then `$CLAUDE_ENV_FILE`. Unknown sessions (no `FLEET_SESSION_NAME`, e.g. ad-hoc/lead) auto-register under a name derived from cwd basename.
- **Per-session files, not one registry file** → zero write contention across concurrent sessions. The dashboard/registry is the *aggregate view* of this directory.

### Identity & transcript resolution
- **Primary key = session name** (launcher-controlled, ≤40 chars). Registry, taskboard, dashboard all key on the name; the registry entry is complete at launch.
- **Conversation/transcript = derived, not handed in.** Resolve `name → repo path → ~/.claude/projects/<slug>/ → newest .jsonl`. The `SessionStart` hook *caches* the real `session_id` into the session file as the authoritative fallback (and to address specific past sessions). Caveat: the cwd→slug transform is an observed convention, not a documented API — cached id is the backstop.

### Inter-session model (same repo) — DECIDED
- **Detection:** two sessions are "same repo" when `git -C <cwd> rev-parse --git-common-dir` matches (worktrees share a common git dir) or they share a `~/claude-sessions/<repo>/` base.
- **Isolation:** each concurrent same-repo session runs in its **own git worktree** (`git worktree add`), so no working-tree clobbering. Distinct cwds → distinct slug/transcript buckets too. Teardown: `git worktree remove` in `/conclude`.
- **Communication (harness-native, NOT agent teams):**
  - *Taskboard* — async handoff (A files a repo-tagged task, B claims it).
  - *Per-repo mailbox* — `~/claude-sessions/<repo>/.fleet/mailbox.jsonl`, append + poll/surface.
  - *`fleet-send <session> "<msg>"`* — relays via `tmux paste-buffer` **only when the target is `idle`** (Stop fired), using the status state machine to inject safely.

### Status state machine (from hook events)
| Event | Status | Notes |
|---|---|---|
| SessionStart | `active` | resolve name via `$FLEET_SESSION_NAME`; cache `session_id` as fallback id |
| UserPromptSubmit / PreToolUse | `working` | bump `latest_activity` |
| Stop | `idle` (= "waiting on input") | bump `latest_activity` |
| SessionEnd | `ended` | move file to `archive/` |

"Waiting on anything" = `idle` (Stop fired, awaiting next instruction). With `--dangerously-skip-permissions`, `PermissionRequest` won't fire, so input-waiting collapses cleanly into `idle`.

### Watchdog / auto-recovery (core goal #1)
A lightweight `fleet-watchdog` loop (tmux pane or `launchd` job; poll ~5s — macOS, no inotify):
- **Dead session:** in registry but `tmux has-session` fails → mark `crashed`, archive, write to `alerts.log`, desktop-notify.
- **Stuck session:** `status=working` but `latest_activity` older than threshold (e.g. 10m) → flag `stuck`, escalate.
- **Recovery = escalate/notify, NOT auto-kill.** Killing an interactive session destroys context. Optional offered action: `claude --resume <id>` in the repo. (Auto-restart only for truly headless tasks — out of scope here.)

---

## Components

### 1. `/background` skill — launch a tracked interactive session
Flow:
1. **Expand the prompt** — Claude rewrites the given prompt to be comprehensive, applies the universal style guide from structured memory (`~/.claude/.../memory/`), and *critically* adds things likely missed. **Show the expanded prompt + confirm before launch** (`--yolo` flag to skip). Avoids auto-expansion drift.
2. **Name** — short, lowercase, ≤40 chars, descriptive.
3. **Repo resolution** — (a) explicit repo if user gave one; else (b) scan past session names for a match and *confirm* reuse (fuzzy auto-reuse is destructive — confirm unless exact); else (c) create new repo at `~/fleet/<name>/` (decision: base dir).
4. **Scaffold** — write `README.md` + `CLAUDE.md` describing the goal; write `.claude/settings.json` with fleet hooks; record `cwd→name` in `index.json` and create `sessions/<name>.json` (status `starting`, prompt, started_at, working_directory).
5. **Launch** — `tmux new-session -d -s <name>`; `cd` to repo; run `claude --dangerously-skip-permissions` **interactively** (not `-p`).
6. **Send prompt** — **wait for `>` prompt** via polling `tmux capture-pane` (with timeout/retry — launch can lag); then **`tmux load-buffer` + `tmux paste-buffer -p`** (bracketed paste; never `send-keys` for multiline); send `Enter` separately to submit.
7. Conversation id is filled in asynchronously by the `SessionStart` hook (correlated by cwd).

**Overlap verdict:** vs background subagents — different (those are non-interactive, die with the session). **Delta justified.**

### 2. Session registry + `claude-dashboard` script
- Registry = aggregate of `sessions/*.json`. Fields: name, prompt, started_at, status, working_directory, claude_conversation_id, current_task, latest_activity.
- `claude-dashboard` renders: **running** (name · task · duration · latest activity · status), **waiting** (status=idle), **previous** (archive/), and the **taskboard**. Polls every 1–2s; refresh is automatic because hooks keep state files current.
- A reaper (folded into `fleet-watchdog`) cross-checks `tmux list-sessions` vs registry to catch sessions that died without `SessionEnd`.

**Overlap verdict:** global cross-session view — nothing does this. **Delta justified.**

### 3. `/taskboard` skill
- Store: `tasks/tasks.json`; ids `t-NNN` from `tasks/seq` allocated under `flock` (concurrency-safe).
- Fields: id, text, repo, session, created_by, created_at, completed_at, claimed_by (session id), status.
- Subcommands: add / remove / clear / (list).
- **De-dupe on create** — skill (in-Claude) checks existing open tasks for semantic duplicates before adding.
- **Claiming mechanism (open decision):** v1 = manual / `/background --task t-001` claims on launch. Auto-pull (sessions polling the board) is a v2 feature with real coordination complexity (claim races) — flagged, not in v1.

**Overlap verdict:** agent teams' shared task list overlaps — but it's experimental and not externally scriptable. Custom **delta justified** given we're not using agent teams.

### 4. `/conclude` skill
- **Self-analysis** — parse this session's transcript (`~/.claude/projects/<proj>/<conversation-id>.jsonl`) for: total tokens (sum `message.usage`), turn count, and heuristics for **token burn / re-prompting / corrected mistakes** (e.g. repeated user corrections, large tool outputs, retries).
- **Learnings writeback** — prompt the user to record learnings into the **existing structured memory scheme** (memory dir + `MEMORY.md` index) and/or the repo's `CLAUDE.md`. Reuse the memory system; don't invent a new one.
- **Teardown** — mark tasks, archive `sessions/<name>.json` → `archive/`, kill the tmux session.

**Overlap verdict:** memory writeback overlaps the built-in memory system (reuse it). Session retrospective (tokenburn/re-prompt) is novel. **Delta justified.**

---

## Cross-cutting risks
1. **Hooks are the single point of truth.** If a hook isn't installed in a repo, that session goes invisible/stale. `/background` must always scaffold hooks; watchdog catches the gaps.
2. **Concurrency** — solved by per-session files + atomic writes; only the task-id counter needs `flock`.
3. **Correlation** — solved by `FLEET_SESSION_NAME` injection (per-process, cwd-independent). Residual risk: env-var inheritance into hooks is standard-but-undocumented; fallback chain is `cwd`/`index.json` → `$CLAUDE_ENV_FILE`. Same-repo sessions are isolated into worktrees, so cwds differ anyway.
4. **Stuck-detection is heuristic** — idle-waiting vs hung is inherently ambiguous; threshold-based, escalate-don't-kill.
5. **`--dangerously-skip-permissions`** — unattended full-permission sessions: documented sandbox-only, no prompt-injection protection, won't run as root. Consider scoping working dirs.
6. **macOS** — requires `tmux`; use polling or `fswatch` (no inotify).

## Build order
- **Phase 0 — foundation:** state dir layout, `fleet-hook.sh` dispatcher, per-session state writer, `index.json` correlation. (Everything depends on this.)
- **Phase 1 — `/background`:** expand→name→repo→scaffold→tmux launch→paste-buffer send. (Validates the tmux gotchas + hook correlation end-to-end.)
- **Phase 2 — `claude-dashboard` + `fleet-watchdog`:** render aggregate + reaper + stuck/dead escalation.
- **Phase 3 — `/taskboard`:** store, ids, de-dupe, subcommands.
- **Phase 4 — `/conclude`:** transcript analysis + memory writeback + teardown.

## Decisions (locked)
1. **Repo base dir:** `~/claude-sessions/<name>/`.
2. **Hook scope:** GLOBAL — hooks installed in `~/.claude/settings.json`; every Claude session reports. ⇒ The dispatcher must **auto-register unknown sessions** (cwd not in `index.json` → create an entry named from cwd basename / session id) so ad-hoc and lead sessions still appear.
3. **Task claiming:** manual / at launch (`/background --task t-001`). Auto-pull deferred to v2.
4. **Prompt expansion:** confirm-before-launch; `--yolo` skips.
5. **Style guide:** no memory dir exists yet (`~/.claude/memory/global/` absent). Phase 0 will scaffold the memory structure (`MEMORY.md` + a `style-guide` entry); until populated, expansion proceeds without a style guide.

## Environment confirmed
- `tmux` installed at `/opt/homebrew/bin/tmux`. macOS (darwin) → poll/`fswatch`, no inotify.
- bash 3.2 (scripts written 3.2-safe); no `flock` CLI (`fleet-task` uses python `fcntl`); python3 3.9.6.

## Build status — DONE & live-tested
All phases built under `~/.claude/fleet/bin/` + `~/.claude/skills/`. Hooks wired
globally in `~/.claude/settings.json`. Validated end-to-end against a real
background session: identity correlation via `FLEET_SESSION_NAME`, SessionStart
conversation-id capture, status state machine, dashboard, transcript+token
resolution, and autonomous task execution.

### Known gotcha (handled): folder-trust prompt
`--dangerously-skip-permissions` does NOT bypass Claude's first-run "trust this
folder" dialog; new repos always hit it. `fleet-launch`'s readiness loop detects
it and sends Enter to accept (default "Yes, I trust"), then waits for the
"bypass permissions on" footer before pasting. Skill auto-launch is hands-off.
