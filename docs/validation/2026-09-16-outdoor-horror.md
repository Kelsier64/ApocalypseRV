# 室外恐怖氛圍與離路物資點驗收

日期：2026-09-16。實測 Godot 4.7.2、Windows、Jolt、OpenGL Compatibility；GPU 為 RTX 4060 Laptop。專案／CI 目標 4.6.1 尚未在本機另跑，不宣稱跨版本結果一致。

## 交付內容

- 生成 v3：每三點兩個主要入口、一個低收益補給。第一棟維修廠在 (135,6,-45)，主要場址採道路局部鏡像模板，步道約 192 m。
- 共用場址資料：停車灣、建築平台、六米緩升坡、步道、1.8 m 窄口、連續圍牆、保留區與跨區邊界。
- 維修廠／倉庫／泵站／研究站四個原創網格外觀，保留正式入口、副本、返回點與穩定 POI ID。四款共用原有室內內容。
- 固定陰天、距離霧、低飽和地表、林帶、高低灌木、倉庫工業網柵與路標；復古 3D 約 540 像素高及輕微固定抖色，F8 切換。Canvas UI 不套用濾鏡，偏好獨立保存。
- 擴大導航至完整碰撞地形；跨帶補齊地形與場址障礙；非同步烘焙結果與伺服器同步分開處理。
- 缺少 generation_version 的檢查點按生成 v2 重建，維持舊地形／碰撞／物資配置／POI ID。檢查點格式仍為 v3。

## 自動測試

| 測試 | 覆蓋範圍 |
|---|---|
| test_outdoor_horror | 100 seed × 9 場址：可重現、長度、坡度、道路距離、有效碰撞邊界、整地支撐、保留步道；seed 42 的實體視線、完整路徑、跨帶路徑、遠端串流場址；室內外效果、原生顯示、視窗尺寸與滑鼠穿透 |
| test_outdoor_traversal | 正式玩家持續行走，攜帶引擎約 38.1 秒到入口，以 E 動作載入副本，返回保留引擎 ID；換成大型油桶走回停車區，無跳躍 |
| test_outdoor_encounter | 正式怪物穿過交錯窄口；遠端旋轉場址跨 chunk 追擊；正式 RV 使用輪胎、油門進入停車區，被窄口阻擋並煞停 |
| test_rv_checkpoint | 新生成版本保存、缺省版本轉為 v2，沿用原有車輛／物資／POI 記憶及引擎保存回歸 |
| test_world_generation / test_roadside_exploration | 明確使用 v2，保留原有 100 seed 地形與近路搜刮回歸 |

測試中的怪物偵測距離放大，以隔離「沿指定路線追擊」；不代表遊戲怪物的新偵測平衡。跨區測試由測試程式排定區塊，測試傳送時暫停單向串流控制，避免重複生成及清掉準備回訪的起點。

導航修正包括：地面高低差不再錯誤跳過導航；路點高度對齊怪物腳底；烘焙後發佈獨立網格並等待 region／map 可查詢。初期測試發現的空導航、重疊細三角形與測試場重複 chunk 已修正，未關閉導航警告掩蓋問題。

`scripts/test.ps1` 完整 runner：資源匯入、30 組 `test_*.gd`、主場景啟動全部 PASS。最後的灌木／裁切／網柵補充另重跑 `test_outdoor_horror.gd` 通過。日誌位置：`.godot/test-logs/`、`.godot/horror-final-scenery.log`。`git diff --check` 通過。受限環境的 OS 憑證讀取訊息由既有 runner 精確排除，沒有忽略腳本錯誤。

## 可見回放與截圖

使用正式主場景、玩家、RV、地形與入口模型的 `outdoor_horror_playground.tscn`。F2 切換固定觀察點，1–4 在同一場址替換外觀；F3 送出連續行走輸入，沒有沿途傳送或跳躍。起點擺位及攝影機屬驗收工具。

| 外觀 | 公路辨認 | 停車處 | 遮蔽路段 | 入口 | 回望 RV |
|---|---|---|---|---|---|
| 維修廠 | [畫面](images/2026-09-16-horror-maintenance-highway.jpg) | [畫面](images/2026-09-16-horror-maintenance-parking.jpg) | [畫面](images/2026-09-16-horror-maintenance-trail.jpg) | [畫面](images/2026-09-16-horror-maintenance-entrance.jpg) | [畫面](images/2026-09-16-horror-maintenance-return.jpg) |
| 倉庫 | [畫面](images/2026-09-16-horror-warehouse-highway.jpg) | [畫面](images/2026-09-16-horror-warehouse-parking.jpg) | [畫面](images/2026-09-16-horror-warehouse-trail.jpg) | [畫面](images/2026-09-16-horror-warehouse-entrance.jpg) | [畫面](images/2026-09-16-horror-warehouse-return.jpg) |
| 泵站 | [畫面](images/2026-09-16-horror-pump-highway.jpg) | [畫面](images/2026-09-16-horror-pump-parking.jpg) | [畫面](images/2026-09-16-horror-pump-trail.jpg) | [畫面](images/2026-09-16-horror-pump-entrance.jpg) | [畫面](images/2026-09-16-horror-pump-return.jpg) |
| 研究站 | [畫面](images/2026-09-16-horror-research-highway.jpg) | [畫面](images/2026-09-16-horror-research-parking.jpg) | [畫面](images/2026-09-16-horror-research-trail.jpg) | [畫面](images/2026-09-16-horror-research-entrance.jpg) | [畫面](images/2026-09-16-horror-research-return.jpg) |

觀察：公路與停車處看見煙囪／水塔／管線／天線的高輪廓；建築本體大多藏在牆後。進入步道後，交錯牆和土坡遮住入口與 RV；入口前出現門廊與暖色燈。遠景辨認靠高輪廓，不靠讀取建築招牌。近距離路面、手持引擎與 E 提示可辨認，HUD 文字沒有套低解析度抖色。

- [正式玩家搬運抵達：38.0 秒](images/2026-09-16-horror-carry-complete.jpg)。日誌 `.godot/horror-visible-walk.log`。
- [F8 原生解析度](images/2026-09-16-horror-native.jpg)。關閉效果後仍保留霧及場景配色；重啟驗收場景確認偏好持續保存。
- [進入室內](images/2026-09-16-horror-interior.jpg)、[室內改變視窗大小](images/2026-09-16-horror-resize-interior.jpg)、[返回室外](images/2026-09-16-horror-return-resized.jpg)：正式互動載入 54 房副本，室內恢復原生畫面，返回後恢復復古效果，背包仍持有同一引擎。可見驗收以 F4 回放正式 E 動作；返回使用原有 manager.leave 流程。

## 效能紀錄

seed 42、三個初始區塊、固定步道路線、可見視窗約 1024×720 client；同機另有 headless 回歸工作，以下不是獨占硬體的正式效能基準。

| 指標 | 實測 |
|---|---|
| 正式玩家持引擎單程 | 38.0167 秒 |
| 可見回放渲染影格 | 6,208 frames |
| 影格時間 median／p95 | 6.06／6.06 ms，約 165 FPS 的上限附近 |
| 可見場景初始建立每帶 | 242.9–349.6 ms；啟動階段同步建立 |
| 額外串流兩帶，headless 幾何測試 | build 288.0／328.2 ms，分幀最大 46.0／37.6 ms |
| 怪物／RV 測試同機負載下串流 | 單獨聚焦測試最大 slice 68.6 ms；完整 runner 與可見副本同時執行時峰值 140.5 ms |

分幀已包含地形取樣、造景及林帶，導航背景烘焙。大型網格／碰撞提交仍有數十毫秒尖峰，重負載下可超過 100 ms；本輪完成紀錄，未宣稱所有硬體都維持 60 FPS 或完全無串流頓挫。

## 驗證邊界

- 100 seed 驗證的是資料與地形取樣；完整物理行走、實體射線與怪物追擊使用代表場址，沒有宣稱 900 場址逐一實機走完。
- 四套截圖使用同一個 seed 42 場址換外觀，遠端旋轉／跨區場址另有自動導航及怪物測試。
- 可見回放有真實玩家移動；怪物追擊及 RV 窄口拒絕主要由自動物理測試驗證，未新增完整五公里可見輪驅重跑。
- 固定陰天；未新增天候、日夜、聲音、敵種、驚嚇事件或室內布局。
- 植被、霧不增加新潛行判定；後方已清理地形仍不支援永久回訪。
