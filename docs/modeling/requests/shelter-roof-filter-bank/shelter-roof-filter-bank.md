# 屋頂過濾設備組 — image-to-3D 建模 request

- **要做什麼**：一組獨立的低矮工業空氣過濾設備，作為屋頂裝飾部件；不含建築外殼、屋頂或環境。
- **替換位置與尺寸方向**：[exterior_extension.tscn](../../../../world/starting_shelter/exterior_extension.tscn) 的 `Visuals/RoofPlantB`。設計包圍盒寬 9 × 高 1.5 × 深 5 m；模型原點在包圍盒中心，Y 向上、主要維修面朝 +Z。沿用節點位置 `(11,12.75,-23)`、單位縮放，保留 `Collision/RoofPlantB`。
- **外觀描述／參考圖 prompt**：一組寬扁的老舊軍用空氣過濾設備，三個並排的灰綠金屬過濾箱連在共同底架上，正面可辨識濾網與維修面板，背面接短而寬的密閉風道；表面鏽蝕、積灰、掉漆，低彩度工業恐怖風格。單獨物件完整呈現，不含建築、人物、文字；無動畫與可開蓋機構。
- **交付位置**：`assets/models/shelter_roof_filter_bank/shelter_roof_filter_bank.glb` 與必要貼圖；可編輯來源放 `art_source/shelter_roof_filter_bank/`。只替換外觀，保留碰撞及導航標記。無參考圖，後續由使用者製作圖片並以 diffuser 建模。

完成情況：獨立過濾設備組保留灰盒；建築本體已直接製作，不在本 request 範圍。
