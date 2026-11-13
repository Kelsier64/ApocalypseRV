# ApocalypseRV Agent Guide

All project instructions live in [CLAUDE.md](CLAUDE.md). Read it before working in this repository; it is the single source of truth. Project skills are in `.claude/skills/<name>/SKILL.md`; read the matching one when its trigger in CLAUDE.md applies.

## Notes for agents without Claude Code hooks

- Run `scripts/agent/session-context.ps1` at the start of a session and `scripts/agent/check-staged.ps1` before every commit; Claude Code does both through hooks.
- Codex: if the sandbox cannot reach Godot (`C:\Program Files\godot\godot.exe`), retry with `sandbox_permissions: "require_escalated"`. For desktop control use `node_repl` with `@oai/sky` in place of the computer-use MCP tools named in the skills.
