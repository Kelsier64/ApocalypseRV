---
name: docs-maintenance
description: Use when editing ApocalypseRV README.md, GDD.md, architecture.md or anything under docs/, when recording validation results, or when a code change makes a document stale.
---

# Docs Maintenance

## Where Things Go

| Document | Contains | Never contains |
|---|---|---|
| `README.md` | What the game is, how to run and play it, entry points to other docs | Dated changelog paragraphs, test results |
| `GDD.md` | Design intent and player-facing rules, plus unbuilt ideas marked as such | Implementation detail |
| `architecture.md` | Current modules, ownership, data flow, contracts and known limits, in the present tense | History, dated entries, per-feature tuning numbers |
| `docs/guides/` | How to work on one area | Status reports |
| `docs/plans/` | One plan per file with a status line; update the status when it changes | Validation logs |
| `docs/validation/` | One dated record per validation run; leave it unchanged afterwards | Current-state claims |
| `docs/archive/` | Frozen history | Anything new |

Existing documents break several of these rules. Do not copy their patterns. When you touch a section, move it toward this layout.

## Writing Rules

- Describe the current state. When a fact changes, replace the old sentence; do not add a dated correction next to it.
- History belongs in `git log` and `docs/validation/`. Do not prepend dated summaries to `README.md` or `architecture.md`.
- Do not hard-code values that drift (version numbers, test counts, file counts). Name the code constant or file that holds them.
- Keep paragraphs short, one topic per section, and link to code instead of restating it.
- Docs are in Traditional Chinese, agent instructions in English, and in-game text in English.
- A validation record lists the commit, what was run, the results, and what remains unverified. Commit the Markdown and at most a few representative images; logs and capture sets stay in `.godot/`.

## Check

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent/check-links.ps1 README.md docs/guides/codebase.md
```

With no arguments it checks every current document, skipping the historical folders. Verify any version, path or behavior you state against code. Docs-only changes do not need Godot.
