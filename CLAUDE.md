# ApocalypseRV

Single-player first-person survival prototype in Godot 4.7.2: drive an RV, scavenge buildings, craft, and survive monsters that climb and wreck the vehicle. **Procedural generation is the core of the game**: world, roads, POIs, interiors, loot and encounters come from seeds and rules, so prefer generative modules over hand-placed one-off scenes (see [GDD](GDD.md#section-1)). Main scene: `world/main_world.tscn`. This file is the entry point for Claude Code project instructions.

## Start Here

Facts that drift (branch state, version constants, test count, last full test result) come from the repository, not from prose. A SessionStart hook prints them via `scripts/agent/session-context.ps1`.

Version constants live in `world/terrain/world_profile.gd` (`generation_version`), `rv/checkpoint.gd` and `rv/vehicle_snapshot.gd` (`VERSION`). For a class index generated from code, run `scripts/agent/module-index.ps1 [filter]`.

Docs lag behind code. [docs/README.md](docs/README.md) is the index: `GDD.md` holds design intent, `architecture.md` cross-module structure, `docs/systems/<system>.md` one system's features, values and contracts, `docs/guides/` how-tos, and `docs/plans/` unfinished work. Read the matching system file before changing a system. A few system files are still merged from older documents and carry dated paragraphs (the list is in [docs/plans/README.md](docs/plans/README.md)): verify a doc claim against code before relying on it, and correct stale statements you touch.

## Map

| Path | Holds |
|---|---|
| `player/`, `enemies/`, `props/` | Actors, interaction, AI, items |
| `rv/`, `equipment/` | Vehicle physics, save checkpoint, mounted devices |
| `world/` | Terrain streaming, chunks, POIs, buildings, interiors |
| `core/` | Shared rules and contracts: items, saves, climbing math, placement, settings |
| `assets/`, `art_source/` | Runtime art; editable sources and build inputs |
| `tests/`, `scripts/` | Automated tests, fixtures, manual playgrounds; runner, builders, agent tools |
| `docs/` | System docs, guides, plans and reference material; index in `docs/README.md` |
| `.claude/` | Skills, hook settings; `.mcp.json` configures the Blender MCP server |

Placement, reference and cleanup rules: [docs/guides/codebase.md](docs/guides/codebase.md).

## Commands

Godot is at `C:\Program Files\godot\godot.exe` and on PATH. Use the PowerShell tool (the Bash tool is Git Bash) and `run_in_background` for test runs and game launches.

```powershell
godot --editor --path .
godot --path .
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
```

The last command imports once, then runs every top-level `tests/test_*.gd` and the main-scene smoke check. It stops at the first failure unless you pass `-KeepGoing`. Load the `godot-tests` skill before choosing, writing or debugging tests.

Python: `python` on PATH may be the Microsoft Store stub. Use `$env:USERPROFILE\Apps\ComfyUI\pixal3d-runtime\.venv\Scripts\python.exe` (Pillow + numpy) or `$env:USERPROFILE\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe` (Pillow). Never install Python globally without asking.

## Hard Rules

1. **In-game text.** Use English and only what the player or setting needs. Never put hints, controls, item names or status in the 3D world, including `Label3D`, `TextMesh`, floating, camera-facing, glowing or unshaded text. Essential prompts belong in screen-space UI. World text is allowed only where the fiction demands it (a physical sign, a maker's plate, an instrument screen). Finish it as integrated texture, decal or device-screen art, and never smuggle hints into textures. This applies to reference images and generated assets too.
2. **Nothing intermediate in Git.** Keep work files, screenshots, recordings, logs, archives and editor backups (`.blend1`) under `.godot/` or another ignored path. Commit only game assets, code, tests, concise docs and at most a few representative evidence images.
3. **Saves are disposable and frozen.** Change save formats directly, delete old local saves when needed, and remove compatibility branches instead of extending them. Save development is paused until late in the project (2026-11-15): keep the current F6/F9 checkpoint and its tests working, but do not extend it for new features; their state may reset on load. One exception: register every new Item or Monster scene in `core/save_scene_catalog.gd`, because the tutorial stage restart and the F6 checkpoint share this whitelist and reject any world that holds an unregistered scene.
4. **Randomness is gameplay; procedural generation is the focus.** Use it for meaningful variation in generation, encounters and loot. Preserve guarantees the player relies on, and use fixed seeds to reproduce a run.
5. **Tests read their baselines.** Never copy tuning values (energy, colors, speeds, timings) from scenes into tests as literals. Read them from the scene or resource under test, or assert relative behavior.

Hooks in `.claude/settings.json` enforce rules 1 and 2: before edits they block `Label3D`/`TextMesh` in game code, and before `git commit` they run `scripts/agent/check-staged.ps1`, which also checks staged docs for broken links and misplaced files. When a hook blocks, fix the cause or ask the user; never route around it.

## Working Defaults

- **Ask before starting** whenever the goal is unclear or the work needs a tradeoff you would otherwise settle yourself. Use `AskUserQuestion` cards with one question per decision, concise options, and your recommendation first. Send more cards when there are more than four questions. Do not start on a guess. Use the cards for decisions that come up mid-work too. A card may hide the text before it, so make each one readable on its own and put drafts in the option preview. Read-only investigation that sharpens the question may come first.
- Report architecture problems you notice. Ask before large architectural changes.
- **Write decisions back to the docs.** Record agent rules in `CLAUDE.md` so later sessions can find them. When the user settles or changes a design, or a change alters behavior a document describes, update the design intent in `GDD.md` and the implementation contracts in the matching `docs/systems/` file in the same change, without being asked. Track features nobody has played yet and problems deferred for later in `docs/plans/README.md`. Delete documents that will not be used again. Git history is the archive. The `docs-maintenance` skill has the placement table.
- Validate with the smallest set that covers the changed behavior and its risks. Skip tests for simple, low-risk edits. For docs-only changes, check wording, consistency, links and placement (`scripts/agent/check-docs.ps1 <files>`); do not launch Godot.
- **Hand hands-on checks to the user.** When a change needs visual, feel or in-game verification, build or reuse a playground scene that sets up the exact state, launch it, and give the user a short checklist of what to look at and report back. Do not ask whether to verify, and do not spend tokens on screenshot loops. Launch commands, `--capture` renders and their pitfalls are in [docs/guides/playgrounds.md](docs/guides/playgrounds.md#啟動與固定截圖). Automated tests still run as usual.
- Report what you checked, what you did not, and any material uncertainty. Never claim visual or hands-on verification you did not do.
- Work token-efficiently: use Grep/Glob, read targeted ranges, batch independent tool calls, and reuse established findings.

## Git

Solo project, trunk-based. The user delegates Git to you: commit and push without being asked.

- **Where.** Work in this checkout on `main` and land it on `origin/main`.
- **Commit** each finished, verified unit of work, one topic per commit. Stage named paths only. Never use `git add -A`, `git add .`, `git commit -a` or `git stash`: other sessions and Codex may have uncommitted work in this checkout. Put test results and what was not verified in the message.
- **Push** at the end of every task that committed something. First `git fetch`, then rebase your unpushed commits onto `origin/main` (another machine pushes to the same `main`), then `git push origin HEAD:main`. Hold the push and report instead when the rebase conflicts or a relevant test fails.
- **Ask first** before force-pushing, `reset --hard`, rebasing or amending pushed commits, switching branches, or deleting branches you did not create.

## Delegation

- Keep scene modeling and 3D integration in the main agent.
- **Use agy (Antigravity CLI, Gemini) only to generate images** (reference images, textures, concept art, icons). Claude has no image generator and local ComfyUI has no text-to-image model. Run it in an empty folder outside the repo and read the result before use; [reference images](.claude/skills/comfyui-image-to-3d/references/reference-images.md) has the tested call and checks.
- Do not send agy code research, doc audits, reviews, log triage or edits. Its results still need a full check, and its failed runs cost more Claude tokens than it saves. To keep the main context small, use an Explore subagent for broad searches and start a fresh session per independent task.

## Skills

Project skills live in `.claude/skills/`. Load one when its trigger applies.

| Skill | Load when |
|---|---|
| `godot-tests` | Choosing, running, writing or debugging automated tests or CI failures |
| `docs-maintenance` | Editing `README.md`, `GDD.md`, `architecture.md` or `docs/`; a design is decided or changed; a code change makes a document stale; a plan starts or finishes |
| `apocalypse-rv-3d-scenes` | Building or editing 3D scenes, or replacing visual assets |
| `comfyui-image-to-3d` | Generating a 3D prop from a reference image with local ComfyUI |
| `harness-maintenance` | Editing CLAUDE.md, `.claude/`, `scripts/agent/` or `.mcp.json` |
