# RV terminal and vehicle TUI

Godot 4.7.2; implemented on `codex/rv-console-ui`.

## Result

Opening the mounted tablet enters an English `rvctl` TUI with Overview, Energy, Equipment, Crafting and Structure pages. The local Noto Sans Mono theme uses character frames, ASCII meters, reverse selection and native keyboard/mouse controls. The console scales to a readable 1280-unit layout on larger game viewports; narrower layouts stack their panels and scroll to focused controls.

Overview owns engine/headlight controls; Equipment owns cabin/service lighting and individual installed-device toggles. Structure presents eleven slots and authoritative repair/rebuild/conversion reasons. Crafting separates recipe selection from queuing and supports workstation selection, progress and cancellation refunds. Brightness, vibration and obsolete work-lamp controls are absent; saved compatibility fields and default effects remain.

Only hidden Ctrl+C/Ctrl+D leave the TUI. Esc closes the tablet from either mode, numeric fields and popup menus without opening settings. Shell starts with only `operator@rv:~$`, input and cursor; output appears only after user commands. `rvctl`, `status`, `help [command]`, `clear` and `exit` use explicit game-command dispatch. `cheat` reserves a future interface and does not mutate state. History restores drafts; completion and pasted text never execute commands.

Both modes retain one player UI owner and one opening fee. Leaving management cancels only construction authorized by that tablet; crafting queues continue. Construction also requires active management at commit time. Every closure dismisses popup windows and latches held gameplay inputs until released. Existing grab, hand, death, power and mounted-support lifecycle closures remain.

## Automated checks run

- Complete `quick` profile: **39/39 PASS**, 134.74 seconds. Includes all three new suites, lighting, crafting, resources and vehicle behavior. Logs: `.godot/test-logs/20261011-204620-857-quick-12456`.
- Related checkpoint, driving-experience, settings and main-scene startup checks: PASS. Crafting print/body, equipment lifecycle and RV systems checks also passed in that run. Its initial construction assertion exposed an abbreviated fee label; the label was fixed and construction passed in the later focused and complete quick runs. Logs: `.godot/test-logs/20261011-204134-512-selected-17864` and `.godot/test-logs/20261011-204529-289-selected-36640`.
- Final operator guard/popup ordering: `test_rv_tablet_ui` and `test_settings_menu` PASS. Logs: `.godot/test-logs/20261011-204857-663-selected-35888`.
- Additional popup Ctrl+D, nonempty history draft and centered front/rear navigation regressions: `test_rv_tablet_ui` PASS. Logs: `.godot/test-logs/20261011-205152-926-selected-42976`.
- `test_terminal_commands` covers parsing, completion purity, reserved cheat, allowed actions, malformed output, single-line output and registration/output bounds. `test_rv_terminal_presenter` verifies English translation and read-only craft eligibility without changing caches, registry, resources or queues.
- `test_rv_tablet_ui` dispatches real keyboard/pointer input, native toggles/fields, repeated command submission, popup Esc, hidden chords, eleven slots, crafting/refunds, construction ownership, close/reopen costs, held movement and lifecycle shutdown.

## Native game observation

Used the installed computer-use skill and a uniquely selected RV Systems Validation game window. Observed readable character frames and reverse selection across all five pages, live Energy settings, distinct front/rear cabin lights, mouse queuing of a gasoline recipe with one material deduction and live queue progress, hidden Ctrl+C to a banner-free prompt, typed `rvctl` returning to TUI, and Esc returning directly to gameplay. The queued recipe finished while the terminal was open. Only review game windows were closed afterward; logs are under `.godot/rv-terminal-visual*.log`.

Full integration/slow/assets profiles were not run. Native observations cover the existing desktop window configuration; automated pointer checks use 1280×720. Unrelated concurrent model/scene work was preserved and excluded from the console commit.

## Follow-up: focus highlighting

Removed latched pressed styling from page, recipe, device and structure selectors: selection stays in the existing model/detail panels, and the active page uses a text asterisk. Only interaction focus uses reverse highlighting. CheckButton ON values use a transparent background, including hovered ON state; focused checked text keeps readable contrast. Native observation confirmed Battery socket stays unhighlighted when another control owns focus, and Gasoline Can loses its highlight after Tab moves to Battery while its selected recipe detail remains intact.

For this correction, `test_rv_tablet_ui` and `test_cabin_light_equipment` both PASS in `.godot/test-logs/20261011-210742-601-selected-38808`. The earlier 39-test result above belongs to the initial redesign; the correction reran these two affected suites. Review logs: `.godot/rv-terminal-highlight-review.log` and `.godot/rv-terminal-highlight-final.log`.
