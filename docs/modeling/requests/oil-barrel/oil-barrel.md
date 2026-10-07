# 油桶 — 建模 prompt

- **要做什麼**：依使用者要求製作可替換現有灰圓柱的低模金屬油桶；先保存需求，交付前遊戲繼續使用灰盒。
- **替換位置與尺寸方向**：[props/oil_barrel.tscn](../../../../props/oil_barrel.tscn) 的 `oil_barrel` 外觀。場景設定尺寸為直徑 **0.65917968 m**、高 **1 m**；原點在桶體中心，Y 向上，底部 Y=-0.5、頂部 Y=0.5。設計指定標籤正面朝 +Z；桶口與桶箍均收在既有體積內。
- **外觀要求**：低彩度工業恐怖風格，暗色磨損漆、清楚的桶箍與封閉桶蓋；鏽跡和小凹痕優先用貼圖，不做高密度雕刻。固定外觀，不新增開蓋或倒油動畫。可參考 [收存原件](../../../../art_source/retired_props/2026-09-29/README.md)，使用新的工作副本，保留原件；原件來源／授權仍未核實。
- **交付位置**（規劃）：`assets/models/oil_barrel/oil_barrel.glb` 與必要貼圖，可編輯來源放 `art_source/oil_barrel/`。只替換外觀，保留根節點與外觀接口、碰撞、質量、物品行為及存檔場景路徑。

完成情況：2026-10-06 已依使用者要求用提供的 GLB 完成 3,000 三角形減面與貼圖烘焙候選，交付至 `assets/models/oil_barrel/oil_barrel.glb`；[來源與製作參數](../../../../art_source/oil_barrel/README.md)、[本輪檢查](../../../validation/2026-10-06-oil-barrel-optimization.md)。正式道具仍使用灰盒；尚待場景整合、正式光照與拾取／回收功能檢查。候選保留原件藍色，尚未按暗色低彩度要求定稿。 本輪：2026-10-07 TRELLIS.2／1024／seed 42／50k 參數已生成 1 個原始候選：[whole](../../../../assets/models/oil_barrel/trellis_50k_20261007/oil_barrel.glb)；未做後期降面，檢查 UNKNOWN（含必要未驗項），未替換正式外觀。詳見 [逐件分析](../../../research/2026-10-07-trellis-50k-requests.md)。
