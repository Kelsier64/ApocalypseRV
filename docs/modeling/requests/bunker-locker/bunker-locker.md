# Bunker Locker - modeling prompt

- **Build:** A dented military personnel locker for guard rooms, barracks and checkpoints.
- **Replace:** `world/poi_kit/furniture/bunker/locker_graybox.tscn:Visuals/Model`. **Design dimensions:** 0.62 W x 1.90 H x 0.58 D m. The graybox dimensions are design targets, not measurements of a finished model.
- **Appearance:** Olive paint worn through to bare steel, bent door edges, a number stencil and a readable handle. Keep the silhouette slim and vertical; one locker, no loose parts. Match the low saturation industrial horror bunker materials.
- **Origin, facing, interface:** The existing StaticBody3D and CollisionShape3D remain in the wrapper. The model origin is the bottom center; its front and handle face local +Z.
- **Delivery:** `assets/models/bunker_locker/` for GLB and textures; `art_source/bunker_locker/` for editable source. Replace only the stated visuals and preserve scene node names, collisions and interactions.

Status: 2026-10-07 TRELLIS.2／1024／seed 42／50k 參數已生成 1 個原始候選：[whole](../../../../assets/models/bunker_locker/trellis_50k_20261007/bunker_locker.glb)；未做後期降面，檢查 UNKNOWN（含必要未驗項），未替換正式外觀。詳見 [逐件分析](../../../research/2026-10-07-trellis-50k-requests.md)。
