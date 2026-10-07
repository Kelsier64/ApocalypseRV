# 屋頂箱式通風機組 — image-to-3D 建模 request

- **要做什麼**：一台獨立的老式工業通風機組，作為避難所屋頂裝飾部件；不包含建築、屋頂或周邊場景。
- **替換位置與尺寸方向**：[exterior_extension.tscn](../../../../world/starting_shelter/exterior_extension.tscn) 的 `Visuals/RoofPlantA`。設計包圍盒寬 6 × 高 2 × 深 4 m；模型原點在包圍盒中心，Y 向上、主要進氣面朝 +Z。沿用節點位置 `(-14,13,-22)`、單位縮放，不改獨立的 `Collision/RoofPlantA`。
- **外觀描述／參考圖 prompt**：單台低矮長方形軍用屋頂通風機組，灰綠掉漆金屬機殼、正面大型防雨百葉、頂部兩個有護罩的排風口，側面維修蓋與鏽蝕接縫，低彩度工業恐怖風格；物件完整、背景乾淨，不含房屋或文字。風扇不要求旋轉，不做內部機械。
- **參考圖**：[透明背景 PNG](shelter-roof-air-handler-image-to-3d-reference.png)。單一完整物件的正面三分之四視角，呈現大型防雨百葉、兩個頂部排風罩及側面維修蓋；僅供 diffuser 外觀輸入，尺寸、原點與朝向仍以上述文字為準。
- **交付位置**：`assets/models/shelter_roof_air_handler/shelter_roof_air_handler.glb` 與必要貼圖；可編輯來源放 `art_source/shelter_roof_air_handler/`。只替換外觀，保留碰撞及導航標記。後續由使用者以參考圖透過 diffuser 建模。

完成情況：2026-10-07 TRELLIS.2／1024／seed 42／50k 參數已生成 1 個原始候選：[whole](../../../../assets/models/shelter_roof_air_handler/trellis_50k_20261007/shelter_roof_air_handler.glb)；未做後期降面，檢查 UNKNOWN（含必要未驗項），未替換正式外觀。詳見 [逐件分析](../../../research/2026-10-07-trellis-50k-requests.md)。

- **生成來源**：內建 `image_gen`，依 [GDD 美術方向](../../../../GDD.md#正式戶外低模與低解析度) 與 [D 修正版](../../../art_targets/outdoor/2026-09-17-d-revision.md)。排風罩形狀與維修蓋細節為可替換的外觀假設，無新增接口或活動機構。

<details>
<summary>實際圖片生成 prompt</summary>

```text
Generate a production-ready image-to-3D INPUT CUTOUT, not concept art. One and only one complete stationary rooftop air handling machine shown in one three-quarter view. IMPORTANT COMPOSITION: the complete machine must occupy at most 68% of image width and at most 65% of image height, CENTERED, with at least 12% empty TRANSPARENT margin at LEFT, RIGHT, TOP and BOTTOM. Every bottom edge and corner must be visible. Broad frontal intake faces camera and +Z in the eventual 3D asset; show the front, the right side, and a modest amount of roof. Orthographic camera or long lens, level machine, minimal perspective distortion. A squat industrial rectangular box, width:height:depth approximate 6:2:4. FRONT: one large inset bank of five or six broad thick downward rain-louver slats, dark gaps. TOP: exactly TWO separate low trapezoid covered exhaust hoods, side by side, with dark recessed openings under the covers. RIGHT SIDE: one broad flush rectangular maintenance panel and restrained corroded seam. The entire object including hoods fits within a simple overall rectangular silhouette. Muted weathered gray-green painted steel, matte broad planar faces and rough low resolution material, sparse brown rust at seams and chipped edges. Functional utilitarian 3D survival horror game asset with chunky low-poly shapes and subdued surface wear, deliberately simple geometry. Soft neutral even lighting. True TRANSPARENT RGBA BACKGROUND. No floor or surface, no cast shadow, no setting. No text or markings of any kind: no letters, numbers, logos, labels, icons, symbols, decals, stripes, axes, watermark. No collage or multiple views, no highly detailed photorealistic textures, no high-poly forms, no fan blades, no added devices, no pipes, no floating parts, no cutoff or tight crop. This is only an isolated visual reference, not a scale drawing.
```

</details>
