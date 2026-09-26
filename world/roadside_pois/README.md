# 路邊小 POI（生成 v6）

六種主題，每種三套靜態場景，均登錄為 `PoiDefinition.WALK_IN`。本地 +Z 朝道路，1 unit = 1 m，根節點不縮放。原始程式化製作來源為 [build_minor_pois.gd](../../scripts/build_minor_pois.gd)；首次建立器拒絕覆蓋，日常直接編輯 `.tscn`。

| 主題 | 0 | 1 | 2 | 次要物資 |
|---|---|---|---|---|
| wreck | 拋錨、開引擎蓋 | 雙車事故 | 翻覆車 | 汽油罐 |
| camp | 單帳 | 雙帳圍火 | 撤離後營地 | 普通電池 |
| shed | 養護棚 | 器材堆場 | 缺損棚架 | 輪胎 |
| checkpoint | 警衛亭 | 沙包陣地 | 檢查車道 | 普通電池 |
| cargo | 貨車尾部 | 堆疊棧板 | 散落貨堆 | 汽油罐 |
| rest | 野餐桌 | 休憩棚 | 林道告示 | 普通電池 |

每個物資點在廢鐵／次要物資中等機率抽選，兩個必出、兩個 50% 機率，合計 2–4 件。`EnemySpawns` 為三個獨立 Marker3D，首次均勻抽取 0–2 隻 Raker，標記不重用。場景自身不生成 actor；`WalkInSites` 統一生成與保存。

場景分離 Visuals、Collision、Furnishings、LootSpawns、AccessPoints、EnemySpawns。主要動線沿前側與中央通道；物資鋪墊沒有阻擋碰撞。物資實際放在地面，需繞行物品而非直接穿過。`minor_appearance.gd` 只複製漆面材質調色、切換無碰撞的 DecorSlot，不改碰撞與標記。金屬表面使用專案既有磨損漆紋理，其他表面使用噪音材質；模型均為專案內製作，沒有新增外部素材。

`building_bounds` 為 (-14,-0.5,-11)／(28,7,20)，`site_bounds` 為 (-16,-0.5,-12)／(32,14,42)，包含前方停車淨空。世界停車區中心距路中心 33 m，場景中心 49 m；12×24 m 停車區與道路座標對齊。RV 可沿進場路線倒車退出，不要求在小場址內迴轉。

修改碰撞、佈局或標記必須處理 content_version；不能只加版本號後讓既有存檔載入不同位置。舊 v2–v5 保留原路旁資產，只有新 v6 使用這套場景。

測試場與命令見 [測試指南](../../docs/guides/playgrounds.md#minor-pois)，本輪結果見 [驗收](../../docs/validation/2026-09-26-minor-pois.md)。
