---
name: apocalypse-rv-docs
description: Maintain ApocalypseRV README.md, GDD.md, architecture.md, and project docs, plans, and validation records.
---

# ApocalypseRV Docs

- Use `README.md` for setup and navigation, `GDD.md` for game design, and `architecture.md` for current implementation. Put procedures in `docs/guides/` and active plans in `docs/plans/`. Update a plan's index row when its status changes.
- Verify behavioral claims in code. Refer to constants for drifting values and replace stale statements in touched sections. Write project docs in Traditional Chinese.
- Put test and playtest history in `docs/validation/`. Include the revision, commands, results, and what remains unverified. Keep full logs and capture batches under `.godot/`.
- Run `scripts/agent/check-links.ps1 <paths>` for changed Markdown.
