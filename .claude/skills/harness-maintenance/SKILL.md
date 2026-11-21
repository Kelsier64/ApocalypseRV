---
name: harness-maintenance
description: Maintain the ApocalypseRV Claude Code harness in CLAUDE.md, .claude/skills, .claude/settings.json, and .mcp.json, as well as shared checks under scripts/agent/. Use when changing those instructions, skills, hooks, or tools.
---

# Harness Maintenance

## Layout

Keep Claude Code configuration and instructions in their own files.

| Piece | Where | Rule |
|---|---|---|
| Project instructions | `CLAUDE.md` | Claude Code's entry point |
| Skills | `.claude/skills/<name>/SKILL.md` | Every Claude Code skill has a row in CLAUDE.md's Skills table |
| Hooks | `.claude/settings.json` | Run `scripts/agent/session-context.ps1`, `guard-edit.ps1`, `check-staged.ps1` (which calls `check-docs.ps1` on staged docs). Keep the bash prefilter so unrelated calls stay cheap |
| MCP servers | `.mcp.json` | Blender (`mcp-for-blender`, safe mode) |
| User-level, outside the repo | `~/.claude/skills/` | Keep empty for this project: a user skill overrides a project skill of the same name, so `co-lead` and `agy` live in `.claude/skills/` |

Use only these entry points for agent guidance. Exclude `AGENTS.md`, `.agents/`, and `.codex/` from routine reads and searches. Keep reusable project tools in `scripts/`.

## Put content in the right place

- **CLAUDE.md**: what applies in every session — map, hard rules, working defaults, delegation choices, skill index. Keep it lean; situational workflows go in skills.
- **Skill**: a workflow needed only sometimes. The description says what it does and when to load it, with the words a request would use. Keep the body under ~200 lines; move details to `references/`, one level deep.
- **Script**: facts that drift (versions, test counts, branch state) come from `session-context.ps1`, never from prose.
- **Hook**: only rules that must never break. A hook that blocks must say why and what to do instead.

When agents keep failing at something, fix it at the narrowest level that works: the relevant skill, then CLAUDE.md, then a hook.

Write harness files in English and in the imperative. Docs under `docs/` stay in Traditional Chinese.

## After changing

1. Links and docs layout: `scripts/agent/check-docs.ps1 <changed .md files>`.
2. Hook scripts: feed a sample payload and confirm both the block and the pass case, for example:

   ```powershell
   '{"tool_input":{"file_path":"' + ((Get-Location).Path -replace '\\','/') + '/world/foo.gd","content":"Label3D.new()"}}' |
     powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent/guard-edit.ps1
   ```

3. `scripts/agent/session-context.ps1` runs clean.
4. Grep for stale references to renamed paths, skills or rules.
5. New or renamed skills and output-style changes take effect in the next session; say so in the report.
