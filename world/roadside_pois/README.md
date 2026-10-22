# 小 POI 資產（路旁生成 v6；世界生成 v17）

六種路旁主題，每種三套靜態場景，均登錄為 `PoiDefinition.WALK_IN`；另有僅越野生成的 [civilian_shelter](civilian_shelter.tscn) 小型民用避難所與 [courtyard_shelter](courtyard_shelter.tscn) 庭院變體。資產定義可由不同放置類別重用：camp／shed 亦支援越野生成；wreck、checkpoint、cargo、rest 僅路旁。本地 +Z 為正面，1 unit = 1 m，根節點不縮放。原始路旁資產製作來源為 [build_minor_pois.gd](../../scripts/build_minor_pois.gd)；首次建立器拒絕覆蓋，日常直接編輯 `.tscn`。

| 主題 | 0 | 1 | 2 | 次要物資 |
|---|---|---|---|---|
| wreck | 拋錨、開引擎蓋 | 雙車事故 | 翻覆車 | 汽油罐 |
| camp | 單帳 | 雙帳圍火 | 撤離後營地 | 普通電池 |
| shed | 養護棚 | 器材堆場 | 缺損棚架 | 輪胎 |
| checkpoint | 警衛亭 | 沙包陣地 | 檢查車道 | 普通電池 |
| cargo | 貨車尾部 | 堆疊棧板 | 散落貨堆 | 汽油罐 |
| rest | 野餐桌 | 休憩棚 | 林道告示 | 普通電池 |

上述六種路旁主題的物資點在廢鐵／次要物資中等機率抽選，兩個必出、兩個 50% 機率，合計 2–4 件。`EnemySpawns` 為三個獨立 Marker3D，首次均勻抽取 0–2 隻 Raker，標記不重用。場景自身不生成 actor；`WalkInSites` 統一生成與保存。

場景分離 Visuals、Collision、Furnishings、LootSpawns、AccessPoints、EnemySpawns。主要動線沿前側與中央通道；物資鋪墊沒有阻擋碰撞。物資實際放在地面，需繞行物品而非直接穿過。`minor_appearance.gd` 只複製漆面材質調色、切換無碰撞的 DecorSlot，不改碰撞與標記。金屬表面使用專案既有磨損漆紋理，其他表面使用噪音材質；模型均為專案內製作，沒有新增外部素材。

上述路旁資產的 `building_bounds` 為 (-14,-0.5,-11)／(28,7,20)，`site_bounds` 為 (-16,-0.5,-12)／(32,14,42)，包含前方停車淨空。世界停車區中心距路中心 33 m，場景中心 49 m；12×24 m 停車區與道路座標對齊。RV 可沿進場路線倒車退出，不要求在小場址內迴轉。

`civilian_shelter` 主體約 18 × 13 m，另有退縮門廳及前廊。水泥厚牆、窗洞、樑柱、斷裂女兒牆、破頂鋼筋、排水管及通風座使用原生網格，沿用專案水泥、鏽蝕金屬及低解析風格；六床、桌椅與補給架為暫用簡模，保留獨立 Furnishings 供之後替換。建築界限為 (-10,-0.5,-7.5)／(20,6.5,17)，場址界限為 (-13,-0.5,-10)／(26,11,24)。前後入口直接通行；首訪必出電池與廢鐵，另有 65% 引擎維修包、50% 廢鐵及 0–2 隻 Raker。詳細檢查見 [民用避難所紀錄](../../docs/validation/2026-10-22-civilian-shelter.md)。

`courtyard_shelter` 為 L 形混凝土建築，北側與西側翼圍出開放庭院，前後入口及兩側室內空間直接相通；沿用同一組水泥與鏽蝕金屬材質。建築界限為 (-11,-0.5,-9.3)／(22,7,19.3)，場址界限為 (-14,-0.5,-12)／(28,11,25)。物資與 0–2 隻 Raker 沿用 WalkInSites 的首訪／回訪保存，內容版本為 1。檢查範圍見 [庭院避難所紀錄](../../docs/validation/2026-10-22-courtyard-shelter.md)。

修改碰撞、佈局或標記必須處理 content_version；不能只加版本號後讓既有存檔載入不同位置。舊 v2–v5 保留原路旁資產，路旁小 POI 規則為 v6。世界生成 v15 將 bunker4、camp、shed 納入獨立越野場址；v16 加入 civilian_shelter，v17 加入 courtyard_shelter（兩者 content_version=1、僅 OFF_ROAD）。當前候選比例為 40% 地堡、10% 民用避難所、10% 庭院避難所、40% 營地／棚屋，實際密度仍受地形避讓影響。v17 沿用 v15 的 RNG 域及原道路／地形串流，但場址種類可能改變，依政策舊世界須重新開局。場址 ID 依生成版本、seed 與網格 row／column 穩定生成。越野場址沿自然地面配置，不帶公路標誌、方向標誌、車道、停車線、林間步道、迷宮或周界牆。

測試場與命令見 [測試指南](../../docs/guides/playgrounds.md#minor-pois)，本輪結果見 [驗收](../../docs/validation/2026-09-26-minor-pois.md)。
