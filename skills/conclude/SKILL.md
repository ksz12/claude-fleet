---
name: conclude
description: End the current session cleanly — analyze it for what could be improved (token burn, re-prompting, repeated mistakes, multi-turn waste), capture learnings into structured memory / the repo's CLAUDE.md, then tear down (archive state, remove worktree, kill tmux). Use when the user says "/conclude", "wrap up this session", "we're done here", or wants a session retrospective.
---

# /conclude — retrospective + clean teardown

## 1. Identify the session
The session name is `$FLEET_SESSION_NAME` if set, else derive it from the
current working directory's basename, else ask. Confirm which session you're
concluding.

## 2. Pull metrics
```
~/.claude/fleet/bin/fleet-resolve-transcript <name> --usage
```
This returns the transcript path + token totals (input/output/cache) and
assistant turn count, parsed from the session's own `.jsonl`.

## 3. Analyze — be specific and critical
Using the metrics plus your view of how the session went, identify concrete
inefficiencies. Look for:
- **Token burn**: large/unnecessary file reads, re-reading the same files,
  bloated tool output, context that could have been narrower.
- **Re-prompting / churn**: places where the user had to correct or restate —
  what initial instruction would have avoided it?
- **Repeated mistakes**: the same error class recurring.
- **Multi-turn waste**: work that took many turns but could have been batched.
Summarize as a short, honest retrospective (wins + what to do differently).

## 4. Evaluate recalled memories (effectiveness loop)
> **Optional — requires the companion [grimoire](https://github.com/ksz12/grimoire)
> memory layer.** If `~/.claude/memory/bin/` is not present, skip steps 4 and 5's
> toolkit commands and just note durable lessons in the repo's `CLAUDE.md`.

The recall hooks log what they injected into this session at
`~/.claude/fleet/sessions/<name>.json` under `.injected_memories[]` (each entry
`{ts, slugs}`). Read it:
```
jq -r '.injected_memories // [] | .[].slugs[]' ~/.claude/fleet/sessions/<name>.json | sort -u
```
For each injected memory, check the transcript for **contradiction only** — did
the session do the *opposite* of an injected directive? Be strict about this:
- A memory that was simply **not applicable** to this session carries **no
  signal** — ignore it. Do NOT penalize it.
- Only a genuine **contradiction** (the directive said X, the work did not-X) is
  actionable. For each one, propose either a re-wording (punchier/why-backed) or
  flag it for the user. Never silently demote or auto-edit a memory.
Surface contradictions in the retrospective; don't mutate memory automatically.

## 5. Capture learnings (ask the user) — via the memory toolkit
Offer to record durable lessons. **If grimoire is installed**, use
`~/.claude/memory/bin/mem-capture` (below). **If not**, record the lesson in the
repo's `CLAUDE.md` and skip the rest of this step. Two tracks:
- **Explicit** — something the user told you to remember, or a high-confidence
  lesson they confirm. Auto-commits (with dedup-on-write):
  ```
  ~/.claude/memory/bin/mem-capture --explicit --scope global|project|fleet \
    --type feedback|user|reference|project --name <slug> \
    --desc "<recall summary>" --triggers "<jobs + aliases>" \
    --expected-use "<the failure this prevents>" [--confidence low] \
    --body "<the fact>" [--why "..."] [--how "..."]
  ```
  Always set `--expected-use` for project/reference/fleet facts (when it saves
  tokens or prevents a mistake) — if you can't, it's probably not worth storing.
  Use `--confidence low` for uncertain facts so they render as verify-first
  guardrails, not asserted instructions.
- **Inferred** — a lesson YOU extracted from the retrospective that the user
  hasn't explicitly blessed. Queue it for review (does not go live until
  approved via `mem-review`):
  ```
  ~/.claude/memory/bin/mem-capture --inferred --session <name> --type <...> \
    --name <slug> --desc "..." --body "..."
  ```
Guidance:
- **Auto-suggest `--triggers` — don't ask the user to write them.** Derive them
  from the lesson yourself by answering: "during which *jobs/tasks* should this
  memory resurface, and what would the user type or run then?" Compose the list
  from four sources:
  1. the core job nouns/verbs in the lesson (e.g. `deploy`, `migration`, `auth`);
  2. **common aliases/synonyms** a future prompt might use instead
     (`deploy` → `ship, release, push live, go to prod`);
  3. concrete **tool/command/file names** tied to the job — these power
     action-time recall via the PostToolUse hook (`gcloud`, `cloud run`,
     `terraform apply`, `Dockerfile`);
  4. the relevant **proper nouns** (service, vendor, repo names).
  Aim for ~5–12 comma-separated cues. Show the user your proposed `--triggers`
  in the confirmation and let them edit — but always arrive with a suggestion.
  Example — lesson "deploys to the api service go through `gcloud run deploy`
  after a cloudbuild": `--triggers "deploy, ship, release, push live, production,
  gcloud, cloud run, cloudbuild, api service"`.
- Pick `--scope`: `global` (applies everywhere), `project` (this repo only),
  `fleet` (shared across sessions).
- Don't hand-manage dedup or `MEMORY.md` — `mem-capture` dedups on write and
  `mem-index` maintains the index.
- Session/repo-specific notes that aren't general lessons still go in the repo's
  `CLAUDE.md`.

**Keep each fact concise; split when it would exceed the injection budget.** A
memory body over ~700 chars is truncated at recall time, so `mem-capture` will
*refuse* it. If a lesson is long or spans multiple jobs/concepts, don't force it
— split into a concise parent + focused sub-facts linked with `[[wikilinks]]`,
each its own `mem-capture` call with its own triggers (one job/concept per file).

**Self-test triggers before committing — don't trust them blind.** After drafting
`--triggers`, dry-run recall (read-only, no side effects):
```
~/.claude/memory/bin/mem-try query "<a phrasing the user would actually use>"
~/.claude/memory/bin/mem-try query "<an unrelated phrasing>"   # must NOT surface it
~/.claude/memory/bin/mem-try tool  "<a command that implies this job>"
```
Confirm the memory surfaces for the intended phrasing/command and does NOT
over-fire on the unrelated one. Tighten the triggers if either fails.

**Lint after committing.** Run `~/.claude/memory/bin/mem-lint` and fix any ERROR
(e.g. a dangerously generic trigger like `run`/`test` that would match most
commands, or an over-budget body). Warnings are advisory.

Confirm what/where with the user before writing.

## 6. Tear down
- If the session claimed a task, ask whether to `fleet-task complete <id>`.
- Archive the session state:
  `mv ~/.claude/fleet/sessions/<name>.json ~/.claude/fleet/archive/` (set
  `status` to `ended` first via jq).
- If this session ran in a git worktree, remove it:
  `git -C <repo_root> worktree remove <working_directory>` (after committing or
  confirming with the user that uncommitted changes can be discarded).
- Kill the tmux session: `tmux kill-session -t <name>` (do this last — it ends
  the session you may be running in; confirm first).

Report what was saved and what was torn down.
