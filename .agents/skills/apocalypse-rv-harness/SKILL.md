---
name: apocalypse-rv-harness
description: Maintain ApocalypseRV Codex instructions, project skills, hooks, and tool settings. Use when editing AGENTS.md, .agents/skills, .codex, or shared agent checks.
---

# ApocalypseRV Codex Harness

- Keep persistent Codex instructions in `AGENTS.md`, reusable workflows in `.agents/skills/`, and native hooks and tool settings in `.codex/`.
- Keep executable project tools under `scripts/`. Give each tool a normal command-line entry point so agents, developers, and CI can run it independently.
- Keep Codex guidance self-contained. Use project code and neutral guides for shared facts. Scope broad searches to the relevant game directories and Codex harness files.
- Keep Markdown instructions in English, player-facing text in English, and project docs in Traditional Chinese.

Run `scripts/agent/check-links.ps1` on changed Markdown. For hook changes, run each configured command with representative allowed and blocked payloads. Check that live context prints from the repo root and from a subdirectory. Open a fresh Codex chat to check discovery and approve repo hooks if the client prompts.
