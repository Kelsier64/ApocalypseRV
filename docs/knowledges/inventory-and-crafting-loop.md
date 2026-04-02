# Knowledge: Inventory and Crafting Loop

## 1. Why This Matters
- Inventory and material conversion connect player looting, RV progression, and equipment utility.
- This loop is central to current survivability and experimentation in the prototype.

## 2. Trigger Conditions
- Modifying player inventory slot behavior or item equip/drop logic.
- Changing prop metadata (`item_name`, `is_large`, `scrap_yields`).
- Editing crafting/scrapping station behavior, tablet recipes, or RV material APIs.

## 3. Canonical Workflow
1. Player picks up props through `interact(player)` and stores them in 6-slot inventory.
2. Large items are single-carry constrained (`has_large_item` lock) and block switching away until dropped/consumed.
3. Scrapper consumes prop objects over time and deposits yielded materials into connected RV inventory.
4. Tablet UI reads RV inventory and recipe costs, then calls crafting station to spawn crafted items if resources are sufficient.

## 4. Commands/APIs/Procedures
- Run scene for manual loop validation:
  - `godot --path . res://world/test_world.tscn`
- Inventory APIs:
  - Player: `add_item`, `consume_active_item`, `drop_item`, `get_active_item_name`
  - RV: `add_item`, `has_materials`, `deduct_materials`, `get_all_items`, signal `inventory_changed`
- Device APIs:
  - `Scrapper.recycle_prop` / `_finish_recycle`
  - `TabletUI.on_open` / `_craft_item`
  - `CraftingStation.spawn_item(scene_path)`

## 5. Edge Cases and Failure Patterns
- Programmatically instantiated props may have empty `scene_file_path`; fallback path logic is limited to oil barrel/scrap shape assumptions.
- Scrapper not under RV ancestry reports offline and will not convert materials.
- Tablet requires a crafting station in group `crafting_stations` connected to the same RV; otherwise craft attempt fails.
- Active slot index can point to empty slots due to fixed 0..5 cycling while inventory length may be smaller.

## 6. Validation Checklist
- [ ] Pick up small and large props; verify slot updates and large-item lock behavior.
- [ ] Drop active item and confirm it spawns in world with expected impulse.
- [ ] Feed scrapper while mounted on RV and verify `inventory_changed`-driven UI refresh.
- [ ] Attempt scrapping off-RV and confirm offline rejection behavior.
- [ ] Craft recipe from tablet with and without sufficient materials and observe expected outcomes.

## 7. Related Modules
- `docs/module/player-and-interaction.md`
- `docs/module/rv-and-equipment.md`

## 8. Source Files Used
- `player/player.gd`
- `player/player_interact.gd`
- `props/interactable_item.gd`
- `equipment/scrapper.gd`
- `equipment/tablet_ui.gd`
- `equipment/tablet_screen.gd`
- `equipment/crafting_station.gd`
- `rv/chassis.gd`

## 9. Completeness Notes
- This document captures implemented inventory/material loops and constraints.
- Recipe content is intentionally minimal in current code (single recipe for gasoline can).
