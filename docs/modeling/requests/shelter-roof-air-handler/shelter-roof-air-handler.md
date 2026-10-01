# 屋頂箱式通風機組 — image-to-3D 建模 request

- **要做什麼**：一台獨立的老式工業通風機組，作為避難所屋頂裝飾部件；不包含建築、屋頂或周邊場景。
- **替換位置與尺寸方向**：[exterior_extension.tscn](../../../../world/starting_shelter/exterior_extension.tscn) 的 `Visuals/RoofPlantA`。設計包圍盒寬 6 × 高 2 × 深 4 m；模型原點在包圍盒中心，Y 向上、主要進氣面朝 +Z。沿用節點位置 `(-14,13,-22)`、單位縮放，不改獨立的 `Collision/RoofPlantA`。
- **外觀描述／參考圖 prompt**：單台低矮長方形軍用屋頂通風機組，灰綠掉漆金屬機殼、正面大型防雨百葉、頂部兩個有護罩的排風口，側面維修蓋與鏽蝕接縫，低彩度工業恐怖風格；物件完整、背景乾淨，不含房屋或文字。風扇不要求旋轉，不做內部機械。
- **交付位置**：`assets/models/shelter_roof_air_handler/shelter_roof_air_handler.glb` 與必要貼圖；可編輯來源放 `art_source/shelter_roof_air_handler/`。只替換外觀，保留碰撞及導航標記。無參考圖，後續由使用者製作圖片並以 diffuser 建模。

完成情況：屋頂獨立機組保留灰盒；建築牆體、屋頂與立面已由場景直接製作，不在本 request 範圍。
