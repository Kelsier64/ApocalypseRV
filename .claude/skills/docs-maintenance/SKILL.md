---
name: docs-maintenance
description: Use when editing ApocalypseRV README.md, GDD.md, architecture.md or anything under docs/, when a design is decided or changed in conversation, when a code change alters behavior a document describes, when finishing or starting a plan, or when deciding where a piece of documentation belongs.
---

# Docs Maintenance

Docs hold what the code cannot say: design intent, rules that span files, how to make things, and what is not done yet. Each fact lives in one place; everything else links to it. [docs/README.md](../../../docs/README.md) is the index.

## Where Things Go

| Content | Place | Never put here |
|---|---|---|
| What the game is, how to run it, controls, terminal commands | `README.md` | Rules, tuning values, history |
| Design intent, player-facing rules, undecided or unbuilt directions (section 9) | `GDD.md` | Implementation detail, tuning values |
| Cross-module structure: scene tree, module responsibilities, shared contracts, state ownership, known limits | `architecture.md` | Anything that belongs to a single system |
| One system's current features, values and implementation contracts | `docs/systems/<system>.md` | Other systems' behavior, plans |
| How to make or operate something (authoring rules, tools, playgrounds) | `docs/guides/` | Descriptions of current game behavior |
| Unfinished work: active plans, pending hands-on checks, backlog | `docs/plans/` | Finished work, test logs, bugs |
| Unfixed bugs: wrong behavior, crashes, flaky tests, assets that do not rebuild | `ISSUES.md` | Unbuilt features, structural limits (`architecture.md`) |
| Material to design against: research, art targets, concept images, mockups | `docs/reference/` | Claims about the current game |
| Provenance, build parameters and import notes for one asset folder | `README.md` beside the asset | Anything outside that folder |

Every system file has the same three sections: `功能一覽` (what exists, with links to source and playground), `規則與數值` (what the player meets), `實作契約` (what the code guarantees). Add a new system file only for a new top-level system, and add its row to the table in `docs/README.md`.

## When To Update

Do the doc update in the same change as the work, without being asked:

| Event | Update |
|---|---|
| The user decides or changes a design in conversation | `GDD.md` for the intent and rule; the matching `docs/systems/` file once it is built. An undecided idea goes to `GDD.md` section 9 |
| Code changes behavior, values or contracts a system file describes | That `docs/systems/` file: replace the old sentences |
| Code changes module boundaries, ownership or a shared contract | `architecture.md` |
| A feature is built but not yet played by a person | Add a row to `待人工驗收` in `docs/plans/README.md` |
| The user confirms a hands-on check | Delete that row |
| A bug is found that will not be fixed now | Add or extend its section in `ISSUES.md`, using the format at the top of that file |
| A bug in `ISSUES.md` is fixed | Delete its section in the fixing commit |
| Work is found that will not be done now | Add a row to `待辦` in `docs/plans/README.md` |
| Work starts that spans several sessions | New `docs/plans/<topic>.md` and a row under `進行中` |
| A plan finishes or is replaced | Move its open items to `待人工驗收` or `待辦`, delete the plan file and its row |
| A control or terminal command changes | The table in `README.md` |

Before editing a system, read its `docs/systems/` file. If a statement there disagrees with the code, the code wins: fix the statement while you are there.

## Writing Rules

- Describe the current state in the present tense. Replace a stale sentence; never add a dated correction beside it, and never write "this round" or "this time".
- Keep no history. Delete a document that will not be used again; `git log` is the archive. There is no archive folder and no per-run validation record. Put test and playtest results in the commit message or PR description, and say what was not verified.
- Do not hard-code values that drift (versions, test counts, file counts). Name the constant or file that holds them.
- Do not copy a rule into a second document. Link to the one place that holds it.
- Keep paragraphs short and one topic per section. Link to code instead of restating it.
- Write docs in Traditional Chinese, agent instructions in English, and in-game text in English.
- Name plan files by topic, without a date.
- The system files were merged from older documents and still carry dated paragraphs and version labels. Rewrite the section you touch; do not copy that style.

## Check

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent/check-docs.ps1
```

It checks every tracked Markdown file for broken relative links and reports files under `docs/` that sit outside the layout above. Pass paths to check only those files. The commit hook runs the same check on staged Markdown. Verify any path, value or behavior you state against code. Docs-only changes do not need Godot.
