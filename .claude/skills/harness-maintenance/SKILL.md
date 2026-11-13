---
name: harness-maintenance
description: Layout and rules for changing ApocalypseRV's agent harness — CLAUDE.md, AGENTS.md, .claude/skills, .claude/settings.json hooks, scripts/agent/*, .mcp.json. Use before editing any of these, when adding, renaming or removing a skill, when another agent's edits reshape the harness, or when agents keep misunderstanding or failing at something.
---

# Harness Maintenance

## Layout

The harness is Claude-first. Keep one source for each thing:

| Piece | Where | Rule |
|---|---|---|
| Project instructions | `CLAUDE.md` | Single source. Never `@import` AGENTS.md; with a CLAUDE.md present, Claude Code does not read it |
| Other agents | `AGENTS.md` | A pointer to CLAUDE.md plus notes for agents without hooks (Codex). No rules of its own |
| Skills | `.claude/skills/<name>/SKILL.md` | The only copy. No `.agents/`, no generated stubs, no sync script. Every skill has a row in CLAUDE.md's Skills table |
| Hooks | `.claude/settings.json` | Run `scripts/agent/session-context.ps1`, `guard-edit.ps1`, `check-staged.ps1`. Keep the bash prefilter so unrelated calls stay cheap |
| MCP servers | `.mcp.json` | Blender (`mcp-for-blender`, safe mode) |
| User-level, outside the repo | `~/.claude/output-styles/co-lead.md`, `~/.claude/skills/{dispatch,agy}` | Cross-project behavior only; project rules never go there |

If an incoming merge brings back `.agents/skills`, generated stubs or an `@AGENTS.md` import, fold the new content into this layout instead of taking it as is.

## Put content in the right place

- **CLAUDE.md**: what applies in every session — map, hard rules, working defaults, delegation choices, skill index. Keep it lean; situational workflows go in skills.
- **Skill**: a workflow needed only sometimes. The description says what it does and when to load it, with the words a request would use. Keep the body under ~200 lines; move details to `references/`, one level deep.
- **Script**: facts that drift (versions, test counts, branch state) come from `session-context.ps1`, never from prose.
- **Hook**: only rules that must never break. A hook that blocks must say why and what to do instead.

When agents keep failing at something, fix it at the narrowest level that works: the relevant skill, then CLAUDE.md, then a hook.

Write harness files in English and in the imperative. Docs under `docs/` stay in Traditional Chinese.

## After changing

1. Links: `scripts/agent/check-links.ps1 <changed .md files>`.
2. Hook scripts: feed a sample payload and confirm both the block and the pass case, for example:

   ```powershell
   '{"tool_input":{"file_path":"' + ((Get-Location).Path -replace '\\','/') + '/world/foo.gd","content":"Label3D.new()"}}' |
     powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent/guard-edit.ps1
   ```

3. `scripts/agent/session-context.ps1` runs clean.
4. Grep for stale references to renamed paths, skills or rules (exclude `docs/validation`, `docs/report`, `docs/archive`, which are historical).
5. New or renamed skills and output-style changes take effect in the next session; say so in the report.
