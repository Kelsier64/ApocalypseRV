# 屋頂過濾設備組 — image-to-3D 建模 request

- **要做什麼**：一組獨立的低矮工業空氣過濾設備，作為屋頂裝飾部件；不含建築外殼、屋頂或環境。
- **替換位置與尺寸方向**：[exterior_extension.tscn](../../../../world/starting_shelter/exterior_extension.tscn) 的 `Visuals/RoofPlantB`。設計包圍盒寬 9 × 高 1.5 × 深 5 m；模型原點在包圍盒中心，Y 向上、主要維修面朝 +Z。沿用節點位置 `(11,12.75,-23)`、單位縮放，保留 `Collision/RoofPlantB`。
- **外觀描述／參考圖 prompt**：一組寬扁的老舊軍用空氣過濾設備，三個並排的灰綠金屬過濾箱連在共同底架上，正面可辨識濾網與維修面板，背面接短而寬的密閉風道；表面鏽蝕、積灰、掉漆，低彩度工業恐怖風格。單獨物件完整呈現，不含建築、人物、文字；無動畫與可開蓋機構。
- **參考圖**：[透明背景 PNG](shelter-roof-filter-bank-image-to-3d-reference.png)。單一組裝物件的正面三分之四視角，呈現三個並排過濾箱、共同底架及後方連續密閉風道；僅供 diffuser 外觀輸入，尺寸、原點與朝向仍以上述文字為準。
- **交付位置**：`assets/models/shelter_roof_filter_bank/shelter_roof_filter_bank.glb` 與必要貼圖；可編輯來源放 `art_source/shelter_roof_filter_bank/`。只替換外觀，保留碰撞及導航標記。後續由使用者以參考圖透過 diffuser 建模。

完成情況：2026-10-01 已由 `image_to_3d_reference` subagent 製作並檢查參考圖；模型尚待生成與接入，獨立過濾設備組保留灰盒，建築本體不在本 request 範圍。

- **生成來源**：內建 `image_gen`，依 [GDD 美術方向](../../../../GDD.md#正式戶外低模與低解析度) 與 [D 修正版](../../../art_targets/outdoor/2026-09-17-d-revision.md)。風道外殼細節為可替換的外觀假設，無新增接口或活動機構。

<details>
<summary>實際圖片生成與修正 prompt</summary>

```text
Initial generation prompt:
Create exactly ONE isolated assembled rigid 3D game prop as a direct image-to-3D reference, shown in ONE orthographic or long-lens three-quarter view. Subject: a wide, low, old military-industrial rooftop AIR FILTER BANK, design proportions approximately 9 meters wide (X) by 1.5 meters high (Y) by 5 meters deep (Z), centered at the bounding-box origin. Exactly THREE substantial rectangular gray-green metal filter boxes side by side across the width, visually joined on ONE common simple low skid/base frame. Their shared front maintenance face is +Z and must face the viewer, with the left or right side also clearly visible; each front box has a clearly readable broad recessed filter grille and one closed maintenance panel, with simple larger vents and a few robust seam lines. Behind the boxes on the -Z side, include ONE short, WIDE, SEALED rectangular rear air duct manifold, visibly attached and understandable from the elevated three-quarter angle; it has a capped solid exterior and no gaping open mouth. Keep all three boxes, the base and rear duct in one continuous plausible assembly. Low camera elevation just enough to reveal the top and rear duct; nearly level, minimal perspective distortion. Whole prop fully visible, centered, ample transparent margin around all sides. Readable low-poly angular forms, simple coarse planar geometry, rough weathered industrial materials, muted desaturated grey-green painted steel with cool gray and earth-brown grime, broad patches of rust, dust and chipped paint. Visually akin to an intentionally crude low-budget 3D horror game asset, with weathered texture but restrained geometric detail. Soft even studio lighting separating primary masses, no cast shadow. GENUINELY TRANSPARENT background with alpha. No ground, floor, platform, environment, people, fog, atmospheric effects, extra props or floating fragments. Absolutely no text or markings: no labels, symbols, arrows, logos, numbers, UI, captions, watermark or decals. No moving parts, no open lids. Avoid photorealism, high-poly sculpting, cartoon flat colors, decorative giant pixels, dithering, VHS effects, cinematic lighting. Exactly one image, no turnaround or collage.

Final edit prompt (input: initial generated PNG):
Edit the supplied single-object transparent PNG. Preserve exactly the same camera angle, framing, transparent alpha background, and the three side-by-side FRONT gray-green filter boxes with their broad filter grilles, closed maintenance doors and shared low skid. Correct the specific rear silhouette: replace the THREE separate tall rectangular enclosures currently behind the boxes with exactly ONE continuous SHORT, WIDE, LOW, SEALED rectangular rear air duct manifold extending horizontally across the full width behind all three boxes. Make its continuous seam and upper plane clear; keep it low enough that the three main filter boxes remain the dominant form. Maintain one fully assembled rigid rooftop industrial prop, no floating parts. The object should read as an intentionally simple low-poly 3D horror-game model; reduce photographic grit and microtexture somewhat into broad patches of dusty paint, rust and chips, keeping muted gray-green steel. No text or markings of any kind. No ground, shadow, props or environment. Keep entire object visible and centered with margin, one view only.
```

</details>
