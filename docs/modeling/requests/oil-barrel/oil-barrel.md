# 油桶 — 建模 prompt

- **要做什麼**：依使用者要求製作可替換現有灰圓柱的低模金屬油桶；先保存需求，交付前遊戲繼續使用灰盒。
- **替換位置與尺寸方向**：[props/oil_barrel.tscn](../../../../props/oil_barrel.tscn) 的 `oil_barrel` 外觀。場景設定尺寸為直徑 **0.65917968 m**、高 **1 m**；原點在桶體中心，Y 向上，底部 Y=-0.5、頂部 Y=0.5。設計指定標籤正面朝 +Z；桶口與桶箍均收在既有體積內。
- **外觀要求**：低彩度工業恐怖風格，暗色磨損漆、清楚的桶箍與封閉桶蓋；鏽跡和小凹痕優先用貼圖，不做高密度雕刻。固定外觀，不新增開蓋或倒油動畫。可參考 [收存原件](../../../../art_source/retired_props/2026-09-29/README.md)，使用新的工作副本，保留原件；原件來源／授權仍未核實。
- **交付位置**（規劃）：`assets/models/oil_barrel/oil_barrel.glb` 與必要貼圖，可編輯來源放 `art_source/oil_barrel/`。只替換外觀，保留根節點與外觀接口、碰撞、質量、物品行為及存檔場景路徑。

完成情況：2026-10-04 已透過本機 Pixal3D API 生成候選（[oil_barrel](../../../../assets/models/oil_barrel/oil_barrel_candidate.glb)），並通過 Godot 4.7.2 匯入與尺寸／原點檢查；[來源、預覽與待整理事項](../../../../art_source/oil_barrel/README.md)。只完成 API 試作，正式場景仍沿用既有外觀，接口與遊戲行為尚未驗收。
