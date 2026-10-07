# Bunker Bunk Bed - modeling prompt

- **Build:** A two tier barracks bunk with abandoned bedding.
- **Replace:** `world/poi_kit/furniture/bunker/bunk_bed_graybox.tscn:Visuals/Model`. **Design dimensions:** 2.00 W x 1.85 H x 0.90 D m. The graybox dimensions are design targets, not measurements of a finished model.
- **Appearance:** Steel frame, thin stained mattresses, one crumpled blanket, paint chips and subtle rust. The ladder and two tiers must read from a distance; avoid debris protruding into aisles. Match the low saturation industrial horror bunker materials.
- **Origin, facing, interface:** Keep the wrapper collision volume unchanged. Origin is bottom center, long axis local X, access/front at local +Z.
- **Delivery:** `assets/models/bunker_bunk_bed/` for GLB and textures; `art_source/bunker_bunk_bed/` for editable source. Replace only the stated visuals and preserve scene node names, collisions and interactions.

Status: 2026-10-07 TRELLIS.2／1024／seed 42／50k 參數已生成 1 個原始候選：[whole](../../../../assets/models/bunker_bunk_bed/trellis_50k_20261007/bunker_bunk_bed.glb)；未做後期降面，檢查 FAIL（含必要未驗項），未替換正式外觀。詳見 [逐件分析](../../../research/2026-10-07-trellis-50k-requests.md)。
