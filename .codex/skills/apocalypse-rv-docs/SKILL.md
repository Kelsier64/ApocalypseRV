---
name: apocalypse-rv-docs
description: Maintain ApocalypseRV README.md, GDD.md, architecture.md, and project docs. Use when editing docs, when a design is decided or changed, when a code change makes a document stale, or when a plan starts or finishes.
---

# ApocalypseRV Docs

- Keep each fact in one place and link to it elsewhere. `docs/README.md` is the index and states the rules.
- Use `README.md` for setup and controls, `GDD.md` for design intent and player-facing rules, and `architecture.md` for cross-module structure. Put one system's features, values, and contracts in `docs/systems/<system>.md`, procedures in `docs/guides/`, unfinished work in `docs/plans/`, and design references in `docs/reference/`.
- Update docs in the same change as the work. Write a decided or changed design into `GDD.md` and the matching system file. Replace sentences in the system file when code changes the behavior it describes.
- Track features that nobody has played yet and problems deferred for later in `docs/plans/README.md`. When a plan finishes, move its open items there and delete the plan file.
- Keep current state only. Delete documents that will not be used again; git history is the archive. Put test and playtest results in the commit message or PR description, with what remains unverified. Keep full logs and capture batches under `.godot/`.
- Verify behavioral claims in code. Refer to constants for drifting values and replace stale statements in touched sections. Write project docs in Traditional Chinese.
- Run `scripts/agent/check-docs.ps1 <paths>` for changed Markdown. It reports broken links and files outside the docs layout.
