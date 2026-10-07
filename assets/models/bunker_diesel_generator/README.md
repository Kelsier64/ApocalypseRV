# Bunker diesel generator

2026-10-07 的固定軍用柴油發電機，供 bunker power hall 使用。

- [bunker_diesel_generator.glb](bunker_diesel_generator.glb)：Y-up、長軸 X、服務面 +Z、底部中心原點。外觀尺寸 3.20 × 1.70 × 1.20 m（含排氣口）。19,968 三角形／20,921 頂點，一個 mesh、一個材質，沒有動畫或碰撞。由 49,923 面來源減少約 60%，保留高模與比較證據。
- [basecolor](bunker_diesel_generator_basecolor.png)、[ORM](bunker_diesel_generator_orm.png)、[normal](bunker_diesel_generator_normal.png)：各 1024×1024；ORM 的 R/G/B 分別是 AO／roughness／metallic，法線使用 glTF tangent-space。GLB 內嵌相同 PNG bytes；外部檔供編輯。
- [可編輯來源、原始生成與重建方式](../../../art_source/bunker_diesel_generator/README.md)。

只接入 [diesel_generator_graybox.tscn](../../../world/poi_kit/furniture/bunker/diesel_generator_graybox.tscn) 的 `Visuals/Model/Generator`。原 `Blockout`／`Cover`／`Stencil` 保留名稱、類型與資料，設定隱藏；wrapper、`Visuals`／`Model` 與 `Collision` 沒有改名或改變物理設定。

皮帶罩網孔主要是貼圖凹凸，背部與底面為生成近似；詳見 [驗證紀錄](../../../docs/validation/2026-10-07-bunker-diesel-generator-skills.md)。
