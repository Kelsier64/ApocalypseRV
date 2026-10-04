# Small-prop carry height after PR21

## Cause and correction

PR21 retained full-sized props, but the carry overlay still positioned ordinary one-handed props at 1.60 m and the flashlight at 1.69 m. The imported character's shoulder is approximately 1.51 m high at idle. Those targets put the wrists above the shoulder and the raised-look poses next to the face.

The standing one-handed hold now follows the animated holding shoulder, with the ordinary prop center 0.19 m below it and the flashlight center 0.21 m below it. This follows the torso's jogging bob as well as idle posture. Stationary prone holds retain their original height profile so the existing crawl downshift does not lower the item twice. Two-handed and corpse support placement retain their existing rules. Authored mesh/root sizes, release from the actual held world transform, and the existing toss velocity are preserved.

At the lower arm angle, a flashlight finger cannot always wrap in a plane perpendicular to the tube. Proximal contacts now use the reachable cylinder surface, including movement along its axis, choosing the contact closest to the natural finger curl. Distal directions continue that curl while clearing the solid barrel by a 1 mm geometric margin. The flashlight palm marker is centered across the tube. The authored wrist rotation remains untouched.

## Native rendered evidence

Godot `4.7.2.stable.official.ed1daf0bf`, OpenGL Compatibility on NVIDIA RTX 4060 Laptop GPU. Before: merged PR21/main `108999d`. After: the scoped shoulder-relative correction. The production player, skeleton, carry overlay and unchanged full-size meshes are instantiated through the carry playground.

All seven ordinary one-handed prop scenes were measured at camera pitches -0.45, 0 and +0.45 rad: flashlight, scrap, battery, engine repair kit, full/empty gas can and wheel. Observer and first-person renders were inspected; the four reported compact props also have close-up grip renders. Desktop input automation was unavailable; these are native game viewport captures, rather than a manual keyboard/mouse playtest.

| Prop | Level wrist before / after (m) | Raised-look wrist before / after (m) |
|---|---|---|
| Flashlight | 1.631 / 1.306 | 1.729 / 1.412 |
| Scrap | 1.565 / 1.316 | 1.656 / 1.414 |
| Battery | 1.567 / 1.318 | 1.657 / 1.414 |
| Engine repair kit | 1.567 / 1.321 | 1.660 / 1.420 |
| Gas can | 1.551 / 1.313 | 1.575 / 1.341 |
| Empty gas can | 1.551 / 1.317 | 1.575 / 1.342 |
| Wheel | 1.575 / 1.377 | 1.627 / 1.435 |

Full-size large silhouettes can still obstruct the view, as requested in #19. The existing wheel's wide side grip exceeds the arm's reach; this report measures its lowered wrist posture and does not claim a new wheel grip solution.

- [Level-look comparison](media/small-prop-height/level.png)
- [Raised-look comparison](media/small-prop-height/look-up.png)
- [First-person comparison](media/small-prop-height/first-person.png)
- [Final flashlight grip close-up](media/small-prop-height/flashlight-grip.png)
- [Before joint measurements](media/small-prop-height/before-metrics.json)
- [After joint measurements](media/small-prop-height/after-metrics.json)

For interactive inspection, `tests/player_carry_playground.tscn` now cycles all seven one-handed scenes. F1 changes viewpoint, F2 changes item, F3 samples walking, F4 changes look pitch, and F5/F6 inspect/orbit the grip.

## Automated verification

The original carry contact, natural wrist, finger curl, thumb direction, flashlight aim and release assertions remain intact. Carry coverage now includes the engine repair kit, checks wrist/elbow height against the actual shoulder during idle and moving look angles, checks that distal flashlight directions clear the solid barrel, and verifies that the four full-sized compact props remain visible and above the floor while prone and stationary.

The relevant local run completed 9/9 checks successfully with the pinned Godot version and separate test saves: `test_player_carry`, `test_flashlight_grab`, `test_flashlight`, `test_player_inventory`, `test_player_item_release`, `test_corpse`, `test_player_large_item_climbing`, `test_player_prone`, and main-scene smoke. Local logs: `.godot/test-logs/20261005-002301-185-selected-29328/`.

All five CI profiles are required on the published exact head. Their terminal status is recorded in the draft PR description. The existing animation handoff, driver bite/release and intermittent outdoor encounter failures documented in [PR21 CI 37206953747](https://github.com/Kelsier64/ApocalypseRV/actions/runs/37206953747) are outside this correction.
