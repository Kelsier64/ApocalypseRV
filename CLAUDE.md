@AGENTS.md

## Claude Code Notes

- Hooks in `.claude/settings.json` do three things. At session start they print live context. Before edits they block `Label3D`/`TextMesh` in game code. Before `git commit` they run `check-staged.ps1`. When a hook blocks, fix the cause or ask the user; never route around it.
- Skills in `.claude/skills/` are generated pointers. Edit the source in `.agents/skills/`, then run `scripts/agent/sync-skills.ps1`.
- Delegation: use the Explore agent for broad read-only searches and `haiku` for simple lookups.
- Desktop control: the `playtest` skill covers the game flow; load the `computer-use` skill before driving the window.
- Python: `python` on PATH may be the Microsoft Store stub. If it fails, use `$env:USERPROFILE\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe` (Python 3.12 with Pillow) or ask the user. Do not install Python globally without asking.
