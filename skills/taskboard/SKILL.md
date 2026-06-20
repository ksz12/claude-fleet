---
name: taskboard
description: Manage the fleet taskboard — add, list, remove, clear, claim, or complete tasks shared across background sessions. Use when the user says "/taskboard", "add a task", "what's on the taskboard", "clear done tasks", or wants to track work across sessions. Tasks get ids like t-001 and are associated with a repo + session.
---

# /taskboard — manage the shared taskboard

The taskboard is backed by `~/.claude/fleet/bin/fleet-task` (storage in
`~/.claude/fleet/tasks/tasks.json`). Each task has: `id` (t-NNN), `text`,
`repo`, `session`, `status` (open/claimed/done), `created_by`, `created_at`,
`claimed_by`, `completed_at`.

## Interpreting the request
- **Add**: "add task X", "/taskboard add X".
- **List/show**: "what's on the board", "/taskboard".
- **Remove**: "remove t-003".  **Clear**: "clear done" / "clear all".
- **Claim**: "session S takes t-002".  **Complete**: "t-002 is done".

## Adding — de-dupe first (your job, beyond exact match)
Before adding, run `fleet-task list --json` and check whether the new task is a
**semantic duplicate** of an existing open/claimed task (same intent, different
words). If so, tell the user it already exists (cite the id) instead of adding.
The script also blocks exact/whitespace/case duplicates, but you catch the
semantic ones.

Then:
```
~/.claude/fleet/bin/fleet-task add "<text>" [--repo <r>] [--session <s>] [--created-by <s>]
```
Associate the task with a repo/session when the user implies one (e.g. "add a
task for the auth session").

## Commands
```
fleet-task list [--status open|claimed|done] [--repo R]   # show board
fleet-task get <id>                                        # one task
fleet-task claim <id> --session <name>                     # a session takes it
fleet-task complete <id>                                   # mark done
fleet-task remove <id>                                     # delete one
fleet-task clear            # remove DONE tasks
fleet-task clear --all      # remove ALL tasks (confirm with user first)
```

Always confirm before `clear --all` or removing a task the user didn't name
explicitly. After any change, show the updated board (`fleet-task list`).
