# Player Interaction and Equipment

## Why
This partition implements the core scavenging loop where players pick up world props, manage a 6-slot personal carry set, and reposition vehicle equipment for survival uptime. The loop exists to support the GDD goals around scavenging, role execution, and movable equipment systems. [Evidence: GDD.md:46, GDD.md:55, GDD.md:56, GDD.md:57, GDD.md:64, GDD.md:65]

## Problem
Without a unified interaction/placement flow, players can accidentally double-trigger interactions, bypass carry constraints, or place physics objects in unstable hierarchies. Current scripts solve this by centralizing interaction timing on the raycast, constraining large-item carry behavior, and finalizing equipment under stable parents with collision exceptions. [Evidence: player/player_interact.gd:28, player/player_interact.gd:39, player/player_interact.gd:56, player/player.gd:38, player/player.gd:67, player/player.gd:243, equipment/equipment.gd:123]

## Goals
1. Enforce inventory capacity and one-large-item carry rule while keeping slot selection responsive. [Evidence: player/player.gd:12, player/player.gd:37, player/player.gd:41, player/player.gd:48, player/player.gd:67]
2. Keep pickup/hold interactions deterministic with clear hold durations and release behavior. [Evidence: player/player_interact.gd:16, player/player_interact.gd:21, player/player_interact.gd:28, player/player_interact.gd:33, player/player_interact.gd:44, player/player_interact.gd:61]
3. Support equipment ghost placement with two orientation modes and safe confirm/cancel paths. [Evidence: player/player.gd:22, player/player.gd:221, player/player.gd:252, player/player.gd:256, player/player.gd:323, equipment/equipment.gd:73, equipment/equipment.gd:108, equipment/equipment.gd:138]
4. Gate crafting by RV connectivity, material availability, and usable power before spawning output. [Evidence: equipment/tablet_ui.gd:117, equipment/tablet_ui.gd:121, equipment/tablet_ui.gd:134, equipment/tablet_ui.gd:145, equipment/tablet_ui.gd:153, equipment/crafting_station.gd:12, equipment/crafting_station.gd:16, equipment/crafting_station.gd:25]

## Tradeoffs
1. Interaction simplicity over contextual complexity: fixed thresholds (1s/2s) are predictable but not per-object configurable in the interaction driver. [Evidence: player/player_interact.gd:21, player/player_interact.gd:33, player/player_interact.gd:61]
2. Pickup debounce via temporary physics-process disable avoids repeat pickup spam but introduces a hardcoded delay. [Evidence: player/player_interact.gd:38, player/player_interact.gd:39, player/player_interact.gd:50, player/player_interact.gd:51]
3. Placement correctness over free simulation: placed equipment remains frozen/static and mask-limited, reducing emergent movement but improving stability on the RV. [Evidence: equipment/equipment.gd:120, equipment/equipment.gd:121, equipment/equipment.gd:132, equipment/equipment.gd:133]
4. Crafting is RV-coupled and station-coupled, which prevents disconnected abuse but blocks local/off-grid crafting behavior. [Evidence: equipment/tablet_ui.gd:119, equipment/tablet_ui.gd:145, equipment/tablet_ui.gd:149, equipment/crafting_station.gd:12, equipment/crafting_station.gd:14]

## Workflow
1. Player looks at a Prop and taps E for quick pickup; Prop sends item metadata and scene path into player inventory and despawns on success. [Evidence: player/player_interact.gd:36, props/interactable_item.gd:16, props/interactable_item.gd:22, props/interactable_item.gd:25, player/player.gd:45]
2. Inventory update triggers slot UI refresh and active-hand visual equip. [Evidence: player/player.gd:52, player/player.gd:60, player/player.gd:76, player/player.gd:93, player/player.gd:103]
3. Player can drop active item with G; system respawns world instance in front of player and removes inventory entry. [Evidence: player/player.gd:215, player/player.gd:151, player/player.gd:160, player/player.gd:168, player/player.gd:178]
4. Holding F for 2 seconds on Equipment starts placement mode, switching object into ghost/kinematic state. [Evidence: player/player_interact.gd:57, player/player_interact.gd:61, equipment/equipment.gd:73, equipment/equipment.gd:82, equipment/equipment.gd:88]
5. During placement, raycast drives transform, orientation mode, and contact offset; LMB confirms, RMB cancels, R toggles mode. [Evidence: player/player.gd:221, player/player.gd:227, player/player.gd:256, player/player.gd:297, player/player.gd:323, player/player.gd:361, equipment/equipment.gd:108, equipment/equipment.gd:138]
6. Tablet UI open refreshes RV linkage, renders inventory/fuel/power state, evaluates craft button state, and crafts via a valid connected crafting station. [Evidence: equipment/tablet_ui.gd:30, equipment/tablet_ui.gd:39, equipment/tablet_ui.gd:46, equipment/tablet_ui.gd:116, equipment/tablet_ui.gd:126, equipment/tablet_ui.gd:138, equipment/tablet_ui.gd:145, equipment/tablet_ui.gd:166]

## Interfaces
1. Player inventory API
   - `add_item(item_name: String, is_large: bool, scene_path: String) -> bool` enforces size/capacity constraints and updates active slot visuals. [Evidence: player/player.gd:37, player/player.gd:41, player/player.gd:48, player/player.gd:52, player/player.gd:56]
   - `get_active_item_name() -> String` and `consume_active_item()` support interaction consumers such as wheel install logic. [Evidence: player/player.gd:122, player/player.gd:127, player/player_interact.gd:17, player/player_interact.gd:23]
2. Equipment placement API
   - `start_placement(player)`, `confirm_placement(transform, parent)`, `cancel_placement()` define placement lifecycle. [Evidence: equipment/equipment.gd:73, equipment/equipment.gd:108, equipment/equipment.gd:138]
   - Player-side placement state entrypoint is `enter_equipment_placement(equip)`. [Evidence: player/player.gd:139, equipment/equipment.gd:90]
3. Crafting API surface
   - Tablet recipe table currently defines Gasoline Can with material costs. [Evidence: equipment/tablet_ui.gd:8, equipment/tablet_ui.gd:10, equipment/tablet_ui.gd:12]
   - Tablet crafting requires RV checks and delegates output spawning to CraftingStation. [Evidence: equipment/tablet_ui.gd:127, equipment/tablet_ui.gd:134, equipment/tablet_ui.gd:153, equipment/crafting_station.gd:11]
   - CraftingStation output consumes RV power and spawns into current world scene at marker/default offset. [Evidence: equipment/crafting_station.gd:25, equipment/crafting_station.gd:33, equipment/crafting_station.gd:37, equipment/crafting_station.gd:39]

## Edge cases
1. Inventory full blocks pickup. [Evidence: player/player.gd:41, player/player.gd:43]
2. Carrying a large item blocks acquiring another large item and blocks slot switching away from the large slot. [Evidence: player/player.gd:38, player/player.gd:49, player/player.gd:67, player/player.gd:68]
3. Interaction release before hold completion converts into quick interact where applicable. [Evidence: player/player_interact.gd:44, player/player_interact.gd:48, player/player_interact.gd:49]
4. Placement ray miss hides ghost and disallows confirmation. [Evidence: player/player.gd:227, player/player.gd:370, player/player.gd:372]
5. Crafting fails on no RV, no power, insufficient materials, missing station group member, or station not connected to selected RV. [Evidence: equipment/tablet_ui.gd:127, equipment/tablet_ui.gd:129, equipment/tablet_ui.gd:134, equipment/tablet_ui.gd:139, equipment/tablet_ui.gd:149]
6. Craft output fails if scene load fails or RV cannot pay output power cost. [Evidence: equipment/crafting_station.gd:20, equipment/crafting_station.gd:22, equipment/crafting_station.gd:25]

## Validation
1. Inventory constraint test: fill 6 slots, verify slot 7 rejection and console message. [Evidence: player/player.gd:12, player/player.gd:41]
2. Large-item lock test: pick one large prop, verify second large pickup fails and slot switching is blocked until drop/consume. [Evidence: player/player.gd:38, player/player.gd:67, player/player.gd:131, player/player.gd:175]
3. Interaction timing test: verify E hold >=1s triggers hold path; release early triggers quick interact path. [Evidence: player/player_interact.gd:33, player/player_interact.gd:44, player/player_interact.gd:49]
4. Placement control test: verify F hold entry, R mode toggle, LMB confirm on valid hit, RMB cancel restore. [Evidence: player/player_interact.gd:61, player/player.gd:221, player/player.gd:252, player/player.gd:256, equipment/equipment.gd:146]
5. Crafting gate test: verify disabled craft when RV disconnected or no power/materials; verify successful spawn through connected station. [Evidence: equipment/tablet_ui.gd:119, equipment/tablet_ui.gd:121, equipment/tablet_ui.gd:124, equipment/tablet_ui.gd:153, equipment/crafting_station.gd:41]

## Related modules
1. RV systems (inventory/materials/power) are required by duck-typed calls from Equipment and Tablet UI. [Evidence: equipment/equipment.gd:57, equipment/equipment.gd:68, equipment/tablet_ui.gd:121, equipment/tablet_ui.gd:124, equipment/tablet_ui.gd:153]
2. CraftingStation specializes Equipment and provides world item output for tablet-driven crafting. [Evidence: equipment/crafting_station.gd:1, equipment/crafting_station.gd:11]
3. Prop interaction bridges world items into player inventory via `interact(player)`. [Evidence: props/interactable_item.gd:16, props/interactable_item.gd:22]

## Source Files Used
1. player/player.gd
2. player/player_interact.gd
3. equipment/equipment.gd
4. equipment/tablet_ui.gd
5. equipment/crafting_station.gd
6. props/interactable_item.gd
7. GDD.md

## Completeness notes
1. This first version documents implemented behavior in the listed scripts, not intended future GDD features beyond this partition. [Evidence: GDD.md:46, GDD.md:64]
2. Assumption: input actions for movement/UI exist in project settings; exact action map definitions are outside this evidence set. [Evidence: player/player.gd:198, player/player.gd:271]
3. Unknown: the exact tablet open/close trigger path from world interactions is not shown in this partition, only UI-side close signal and open refresh hook are present. [Evidence: equipment/tablet_ui.gd:3, equipment/tablet_ui.gd:30]
4. Unknown: exact RV class contract and signal payload definitions are inferred from duck-typed checks and signal names, not from RV source files in this scope. [Evidence: equipment/equipment.gd:57, equipment/tablet_ui.gd:99, equipment/tablet_ui.gd:111, equipment/tablet_ui.gd:113]
