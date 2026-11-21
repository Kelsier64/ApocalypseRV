# Northline 加油站（已封存）

共用規範見 [POI 製作規範](../../../docs/guides/poi-authoring.md)，舊定義保存於 [Northline 封存區](archive/northline.tres)。類型為 WALK_IN，AccessPoints 的 local -Z 朝建築外側。

`gas_station.tscn` 是 NORTHLINE 公路加油站。從公路可見雙面油價牌、中央折低的雙翼雨棚與分叉鋼柱。加油島後方左側是棋盤地磚的商店，右側是附工具掛板的維修間。兩室相通，可從商店穿過後門繞到維修間，再回到前院。

## 使用

將場景拖入已整平的室外場景，根節點保持單位縮放。原點是地面 Y=0，店面朝 +Z。商店位於 Z=-16～-4，加油棚以 Z=7 為中心。依定義的 site_bounds 保留 X=-18～18、Z=-20～22 的空間，讓 RV 進出，並留出後門步道。

- `Visuals`：店面、玻璃、屋頂、招牌及棚架，可換成同尺寸模型。
- `Collision`：獨立靜態碰撞；玻璃有碰撞，前門、維修間與後門保持開口。
- `Furnishings`：共用貨架、工作桌、櫃子和 `fuel_pump.tscn` 實例，各自持有碰撞。
- `LootSpawns`：PoiLootPoint，只提供物資候選；建築載入不自行產生道具。家具也有既有物資點。
- `AccessPoints`：前門、後門、維修間和測試出生標記，不觸發傳送。
- `Lights`：建築固定照明，測試用常亮，未接 RV 電力。

四座加油機已停用。玩家可在店內的櫃台和維修間找到汽油罐，帶回 RV 加油。門洞常開，雨棚兩側斜面與店面屋頂均有碰撞。

## 測試入口

```powershell
godot --path . --log-file .godot/gas-station.log res://tests/playgrounds/gas_station_playground.tscn
```

正式玩家、完整 RV、固定種子物資與室外導航共用一個世界。WASD／滑鼠移動、E 拾取、G 丟棄；RV 沿用一般駕駛操作。

| 快捷鍵 | 功能 |
|---|---|
| F1 | 回到玩家視角、繼續步行 |
| F2 | 室外總覽 |
| F3 | 商店展示 |
| F4 | 維修間展示 |
| F5 | 從前院開始持續輸入步行回放 |
| F6 | 加油機近看 |
| F7 | 切換四座加油機的原灰盒／GLB 外觀，碰撞保持相同 |
| F8 | 保存目前畫面到 `.godot/gas-station-preview.png` |

展示視角暫停玩家物理，RV 及世界仍運作。F5 只在測試開始重設玩家位置，之後用正式移動輸入走完商店、後門、後院、維修間、內部連通口及前院；不沿路傳送，不刷新物資。重開整個測試場才重建物資。本場景不支援檢查點保存；F6 在此處是模型近看，不是主世界的保存操作。

在啟動指令後加上 `-- --capture`，可擷取玩家進站、前院全景、商店與維修間四個視角，輸出至 `.godot/northline-captures/` 後退出。雨棚、加油機及招牌素材見 [模型說明](../../../assets/models/gas_station/README.md)。

## 主世界接入狀態

Northline 僅供上述獨立場開啟。正式路旁主要停靠點使用 [Orbit](../../poi_definitions/orbit_plaza.tres)。
