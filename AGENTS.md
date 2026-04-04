<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific task, skip this.
</SUBAGENT-STOP>

<EXTREMELY-IMPORTANT>
If you think there is even a 1% chance a skill might apply to what you are doing, you ABSOLUTELY MUST invoke the skill.

IF A SKILL APPLIES TO YOUR TASK, YOU DO NOT HAVE A CHOICE. YOU MUST USE IT.

This is not negotiable. This is not optional. You cannot rationalize your way out of this.
</EXTREMELY-IMPORTANT>

## Instruction Priority

Superpowers skills override default system prompt behavior, but **user instructions always take precedence**:

1. **User's explicit instructions** (CLAUDE.md, GEMINI.md, AGENTS.md, direct requests) — highest priority
2. **Superpowers skills** — override default system behavior where they conflict
3. **Default system prompt** — lowest priority

If CLAUDE.md, GEMINI.md, or AGENTS.md says "don't use TDD" and a skill says "always use TDD," follow the user's instructions. The user is in control.

## How to Access Skills

Use OpenCode's native \`skill\` tool to list and load skills.


# Using Skills

## The Rule

**Invoke relevant or requested skills BEFORE any response or action.** Even a 1% chance a skill might apply means that you should invoke the skill to check. If an invoked skill turns out to be wrong for the situation, you don't need to use it.

```dot
digraph skill_flow {
    "User message received" [shape=doublecircle];
    "About to EnterPlanMode?" [shape=doublecircle];
    "Already brainstormed?" [shape=diamond];
    "Invoke brainstorming skill" [shape=box];
    "Might any skill apply?" [shape=diamond];
    "Invoke skill tool" [shape=box];
    "Announce: 'Using [skill] to [purpose]'" [shape=box];
    "Has checklist?" [shape=diamond];
    "Create todowrite todo per item" [shape=box];
    "Follow skill exactly" [shape=box];
    "Respond (including clarifications)" [shape=doublecircle];

    "About to EnterPlanMode?" -> "Already brainstormed?";
    "Already brainstormed?" -> "Invoke brainstorming skill" [label="no"];
    "Already brainstormed?" -> "Might any skill apply?" [label="yes"];
    "Invoke brainstorming skill" -> "Might any skill apply?";

    "User message received" -> "Might any skill apply?";
    "Might any skill apply?" -> "Invoke skill tool" [label="yes, even 1%"];
    "Might any skill apply?" -> "Respond (including clarifications)" [label="definitely not"];
    "Invoke skill tool" -> "Announce: 'Using [skill] to [purpose]'";
    "Announce: 'Using [skill] to [purpose]'" -> "Has checklist?";
    "Has checklist?" -> "Create todowrite todo per item" [label="yes"];
    "Has checklist?" -> "Follow skill exactly" [label="no"];
    "Create todowrite todo per item" -> "Follow skill exactly";
}
```

## Red Flags

These thoughts mean STOP—you're rationalizing:

| Thought | Reality |
|---------|---------|
| "This is just a simple question" | Questions are tasks. Check for skills. |
| "I need more context first" | Skill check comes BEFORE clarifying questions. |
| "Let me explore the codebase first" | Skills tell you HOW to explore. Check first. |
| "I can check git/files quickly" | Files lack conversation context. Check for skills. |
| "Let me gather information first" | Skills tell you HOW to gather information. |
| "This doesn't need a formal skill" | If a skill exists, use it. |
| "I remember this skill" | Skills evolve. Read current version. |
| "This doesn't count as a task" | Action = task. Check for skills. |
| "The skill is overkill" | Simple things become complex. Use it. |
| "I'll just do this one thing first" | Check BEFORE doing anything. |
| "This feels productive" | Undisciplined action wastes time. Skills prevent this. |
| "I know what that means" | Knowing the concept ≠ using the skill. Invoke it. |

## Skill Priority

When multiple skills could apply, use this order:

1. **Process skills first** (brainstorming, debugging) - these determine HOW to approach the task
2. **Implementation skills second** (frontend-design, mcp-builder) - these guide execution

"Let's build X" → brainstorming first, then implementation skills.
"Fix this bug" → debugging first, then domain-specific skills.

## Skill Types

**Rigid** (TDD, debugging): Follow exactly. Don't adapt away discipline.

**Flexible** (patterns): Adapt principles to context.

The skill itself tells you which.

## User Instructions

Instructions say WHAT, not HOW. "Add X" or "Fix Y" doesn't mean skip workflows.


## Agent Documentation Workflow

### Required Docs Structure
- docs/architecture.md
- docs/design/*.md
- docs/modules/*.md
- docs/knowledge/*.md

### Required Behavior

*If docs/architecture.md is missing, DO NOT use skill:maintaining-docs-sync*

1. If docs/architecture.md exists and the task needs project context, read docs directly before any code edits 
(start with docs/architecture.md than other task-related docs). 
2. During implementation, if docs and code diverge and docs/architecture.md exists, REQUIRED SKILL: use superpowers:patching-docs-mismatch to patch mismatches (always uses subagent dispatch).
3. At task completion and docs/architecture.md exists, REQUIRED SKILL: use superpowers:maintaining-docs-sync to verify docs/code alignment. If mismatches found, route to superpowers:patching-docs-mismatch before completing.

### Reading Priority
1  task-related ./*.md 
2. docs/architecture.md
3. task-related docs/*.md  
*Never re-read AGENTS.md since you auto-load it*
4. task-related docs/design/*.md
5. task-related docs/modules/*.md
6. task-related docs/knowledge/*.md


## User Preferences
Regardless of the language of user's input, please perform your internal reasoning and tool interactions in English and then translate the final output to Traditional Chinese with a concise and direct tone.
For user-facing interactions that need clarification, confirmation, or explicit choices, prioritize the **question** tool instead of freeform follow-up prompts.


<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific task, ignore this.
</SUBAGENT-STOP>








## Project Overview

ApocalypseRV is a cooperative first-person survival game built with **Godot 4.6**, **Jolt Physics**, and **GL Compatibility** renderer. Players drive an RV through a procedurally generated post-apocalyptic highway, scavenging buildings, crafting upgrades, and fighting zombies.

## Commands

```bash
# Run the game (main scene: res://world/test_world.tscn)
godot --path . res://world/test_world.tscn

# Run a generation script headlessly
godot --headless -s <script.gd>

# Python offline tools (not Godot runtime)
uv run main.py
uv run test_building_gen.py
```

## Development Rules

- **Python**: Always use `uv` (`uv run <path>`)
- **Simple scenes**: Edit `.tscn` directly only for simple tasks
- **Complex scenes**: Write `SceneTree` generation scripts and run with `godot --headless -s`; always create fresh scripts under ./scripts (never reuse to avoid overwriting manual edits)
- **Editor tasks**: Provide `.gd` files + step-by-step Editor UI instructions instead of editing `.tscn` directly
