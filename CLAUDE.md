@AGENTS.md

## Claude Code Notes

- Skills: entry points in `.claude/skills/` point to the shared sources in `.agents/skills/`. Read the source `SKILL.md` and resolve its relative links from its own folder.
- Delegation: use the Explore agent for broad read-only searches and a general-purpose agent for independent checks. Pick `haiku` for simple lookups and the session model for deep reasoning.
- Desktop control: load the `computer-use` skill before driving the game window.
- Python: `python` on PATH may be the Microsoft Store stub. If it fails, use the runtime bundled with Codex, `$env:USERPROFILE\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe` (Python 3.12 with Pillow), or ask the user. Do not install Python globally without asking.
