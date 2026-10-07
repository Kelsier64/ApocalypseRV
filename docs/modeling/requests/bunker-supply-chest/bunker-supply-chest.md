# Bunker Supply Chest - modeling prompt

- **Build:** A searchable military supply chest with a moving lid.
- **Replace:** `world/instances/bunker_cache.tscn:Visuals/Body and Visuals/LidPivot/Lid`. **Measured existing cache dimensions:** collision 0.90 W x 0.75 H x 0.70 D m; visible body 0.88 W x 0.62 H x 0.68 D m; visible lid 0.92 W x 0.11 H x 0.72 D m.
- **Appearance:** Small olive steel chest, clasp, worn stencil, handle, scratched corners and supply markings. Body and lid must be separate meshes so the existing search animation still opens the lid. Match the low saturation industrial horror bunker materials.
- **Origin, facing, interface:** Measured from the current cache scene. Keep root StaticBody3D, Collision, Status and script untouched. Origin bottom center; front is local +Z. Preserve the measured Visuals/LidPivot position (0, 0.68, -0.30) m and its rear hinge along local X; the measured Lid mesh offset from the pivot is (0, 0, 0.30) m. A standalone supply_chest_graybox.tscn is a dimensional reference, but the runtime cache scene is the replacement target.
- **Delivery:** `assets/models/bunker_supply_chest/` for GLB and textures; `art_source/bunker_supply_chest/` for editable source. Replace only the stated visuals and preserve scene node names, collisions and interactions.

Status: 2026-10-07 TRELLIS.2／1024／seed 42／50k 參數已生成 2 個原始候選：[body](../../../../assets/models/bunker_supply_chest/trellis_50k_20261007/body.glb)、[lid](../../../../assets/models/bunker_supply_chest/trellis_50k_20261007/lid.glb)；未做後期降面，檢查 UNKNOWN（含必要未驗項），未替換正式外觀。詳見 [逐件分析](../../../research/2026-10-07-trellis-50k-requests.md)。
