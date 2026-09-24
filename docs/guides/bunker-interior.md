# 隨機軍事地堡：房型製作與保存契約

2026-09-24。適用 `bunker`／布局版本 3。實作依據為 [已確認計畫](../plans/2026-09-24-random-bunker.md)，共用場址與資產規範見 [POI 製作規範](poi-authoring.md)。這是基本軍事地堡外觀，精細破損、完整地表設施與玩法內容尚未製作。

## 生成及遊玩

所有既有副本入口共用地堡，初訪抽取 10–30 個模組與 1–3 層目標；入口、通道及樓梯計入總數。無平面邊界，全部接口候選耗盡即停止，允許低於 10 間。各樓層共用普通房池，向地下 B1／B2／B3 延伸，未找到合法跨層安置時保留較少樓層。沒有必出主路、分區、物資、怪物、目標或鎖門捷徑。

入口房牆上的 EXIT 按 E 返回地面。M 顯示已探索地圖，Page Up／Down 切層，未探索房間不顯示。室外世界仍繼續運行。玩家帶入並丟下的物品可保存，室外 F6／F9 使用原檢查點；不支援副本內直接磁碟存檔或任意 Equipment 的室內保存。

## 第一批模組

| 分類 | 尺寸 m | 變體數 | 分類權重 |
|---|---|---|---|
| passage | 3×6 | 2 | 18 |
| corridor | 3×12 | 2 | 12 |
| small | 6×6 | 3 | 25 |
| medium | 6×9 | 2 | 22 |
| large | 9×12 | 2 | 15 |
| hall | 12×18 | 3 | 8 |
| entry | 6×6 | 1 | 專用 |
| stairs | 6×12 | 1 | 跨層嘗試 |

通道淨高 3 m、普通房 3.6 m、大廳 4 m；初始層距 4.5 m。樓梯淨空盒高 7.5 m，跨兩層，9 m 坡長升高 4.5 m，連續楔形碰撞搭配可見踏步、兩端平台與護欄。地板表面為房間原點 Y=0，樓板在下方 0.25 m；+X 東、-Z 北，根節點保持單位縮放。

牆厚 0.24 m，**整片牆必須落在自身占用範圍內**。相鄰房間不把可見面放在相同平面。未接通接口填成混凝土牆並延續下半部塗裝，移除其門框；不偽裝成可開的門板。基本陳設避開完整門寬與門內 2 m 進出區。

## 新增房型：只改場景與資源

1. 複製 `world/poi_kit/rooms/bunker/` 中接近的 `.tscn`，設定新 `room_id`、`footprint: Vector2`（公尺）、`clear_height`。7.5×15 m 合法，不受 3 m 或整數格限制。
2. 同步編輯實際牆板、碰撞與家具，保留 Visuals／Collision／DoorSockets／Furnishings／Walkway。可換 Visuals/Model GLB，不把碰撞放進可替換外觀。
3. `PoiDoorSocket` 原點在門底中央，local -Z 朝外、Y 朝上。設定穩定 socket_id、完整 transform、opening 與 interface_type。首批是 `bunker_240`／2.4×2.8 m；支援偏置門及同牆多門，接口需留出牆角厚度與實際膠囊淨空。`frame_nodes` 指向可在封牆時移除的純視覺門框。
4. 建立 `InteriorRoomDefinition` 資源：穩定 id、content_version、PackedScene、role（ordinary／entry／stairs）、selection_group、weight、enabled。尺寸與接點直接由場景讀取，不複製座標。
5. 登錄到 `world/instances/catalog/bunker.tres`。新增分類時在 group_weights 加權重；先抽分類再抽變體，新增變體不增加整類初選機率。weight=0 或 enabled=false 的版本不參與新生成，但仍可供舊存檔解析。
6. 執行 Profile.validate、布局測試及預覽。普通房 Walkway 第一個 Marker 是可走的導航錨點；entry 必須提供 Walkway/Spawn 和 Walkway/Exit；樓梯上下 socket 必須與 Profile 層距吻合。

完整占用是地板到屋頂的矩形 AABB。L 型／凹形房可使用保守外包盒，不能把其他房塞進凹角。90° 旋轉由接口計算；新增尺寸、普通房與分類不改生成器。電梯、攀爬等新移動機制需另寫程式。

可參考驗收用的 [7.5×15 m 場景](../../tests/fixtures/bunker_extension/expansion.tscn) 與 [新分類資源](../../tests/fixtures/bunker_extension/expansion.tres)。它有實際牆板、碰撞與同牆雙門，只由測試 Profile 登錄，不會增加正式首批 16 模組的數量。

`scripts/build_bunker_kit.py` 是首批場景來源，遇到既有 kit 會在寫入前拒絕。後續直接編輯場景／Resource，不重跑覆蓋手工內容。

## 生成與保存邊界

`InteriorLayout` 只生成可序列化 manifest。從可擴展 socket 隨機選點，按群組／變體權重列出不重複候選，檢查每個可配接口、完整三維占用與樓層；單一候選失敗繼續，單一接口耗盡繼續其他接口。樓梯以 20% 機會優先嘗試，接近房數預算時提高優先；與新層首房原子加入，合計兩模組。對齊的剩餘接口在結尾接成自然環路。

`PoiInterior` 使用相同 manifest 組裝實際碰撞，等待導航烘焙、region 與 map 同步，並確認每個房間錨點可抵達後才交還控制。缺資源、非法內容、烘焙失敗由轉場取消復原，不能冒充正常少房。

保存 version、profile、seed、target_rooms、target_floors、floor_spacing、每房 id／definition／content_version／transform／connections，以及帶 socket ID 的 links／edges、explored、actors。驗證逐一檢查版本、正交旋轉、樓層、三維排斥、接口對齊及整圖連通，不依當前 seed 重抽。新增房型、改 enabled 或權重不改變已保存布局。

更動尺寸、碰撞、接點或家具通路時另開內容版本並保留舊資源；舊版可設 enabled=false。缺少被保存引用的版本明確拒絕；只換不影響占用／碰撞的外觀可沿用。初次遷移只清除已識別的 v1 actor-only／v2 maintenance_v2 舊 POI，其他世界資料保留，讀取不改寫來源檔。未知新版本仍拒絕。

## 預覽與驗收

```powershell
godot --path . --log-file .godot/bunker.log res://tests/bunker_playground.tscn -- --seed=42 --rooms=12 --floors=3
godot --path . --log-file .godot/bunker-replay.log res://tests/bunker_playground.tscn -- --seed=42 --rooms=12 --floors=3 --replay
godot --path . --log-file .godot/bunker-main.log res://tests/poi_instance_playground.tscn -- --replay
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -TestFilter 'test_interior_*.gd' -TimeoutSeconds 240
```

F1 步行、F2 總覽、F3 掀頂（碰撞保留）、F5 連續輸入搬運回放、R 重建、F8 截圖。命令未提供 rooms／floors 時依 seed 隨機。回放用測試引擎驗證大型搬運，不是正式物資生成。完整結果與未測限制見 [驗收](../validation/2026-09-24-random-bunker.md)。
