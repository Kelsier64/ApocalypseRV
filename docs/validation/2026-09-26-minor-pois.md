# 路邊小 POI 重製驗收

日期：2026-09-26–27。Godot 4.7.2、Windows、實機 Forward+／RTX 5070 Ti。基準 commit `a2d9423a80c059613f228527bc16a200e08eae9b`，本輪在含使用者既有修改的工作樹驗證；未提交其他人的玩家耐力、檢查點與匯入設定變動。

## 本輪內容

生成 v6、六主題各三套靜態 WALK_IN、獨立小場址分布、2–4 件物資與 0–2 隻 Raker；整地／導航／串流／戶外保存共用同一場址計畫。舊 v2–v5 保留原配置。操作與場景規格見 [測試場](../guides/playgrounds.md#minor-pois)、[資產](../../world/roadside_pois/README.md)。

## 自動檢查

- `test_minor_site_generation.gd`：1,000 seeds × 12 區間，共 11,509 處；平均 1,251.2 m 一處，觀測相鄰間距 308.1–4,350.3 m。全部 18 套及兩側出現，正反查詢順序結果一致；起點安全區、主／小場址分離、停車支撐、物資地面及舊版排程通過。
- `test_outdoor_minor_assets.gd`：18 套逐一完成真實玩家持續輸入步行、所有物資接近點導航、E 拾取、汽油罐搬運與返回 RV 旁；物資支撐及敵人出生碰撞檢查通過。測試繞過實體物品，沒有把直線穿越物品當作必要路徑。
- `test_outdoor_minor_persistence.gd`：正式 seed 0／cell 0。兩隻敵人中一隻受傷、一隻擊殺；拾取、搬動物資、帶入物品，卸載後寫入磁碟、讀檔並回訪，剩餘物件身分／移動後位置／受傷敵人生命保留，沒有補貨或復活；活動保存沒有休眠副本。保存測試暫停 AI，避免攻擊干擾所有權檢查。
- `test_poi_definitions.gd`：原 v2／v3／v4 場址、地形、ID 與物資資料雜湊保持相同。另由原始 commit 取得 v5 四個 seeds、各 12 個場址的基準，與目前實作逐位元相同，並加入 `test_minor_site_generation.gd` 固定雜湊回歸。
- `test_outdoor_minor_navigation.gd`：正式 seed 2／cell 0 橫跨 900 m 區塊邊界，公路至四個物資接近點均有導航；正式玩家由公路進入、走到物資再返回，鄰區串流保護通過。
- 完整 runner 初次執行在地堡導航 readiness 停止。`test_interior_doorways` 及 `test_interior_navigation` 改用 runner 既有的固定 60 Hz 執行方式後通過，未修改地堡幾何或放寬斷言；隔離的原始 commit 測試也曾通過，故不把初次失敗判定為已證實的既有缺陷。完整執行中斷後，以同一 `scripts/test.ps1 -TestFilter` 分批補跑，最終 73 項測試、資產匯入與主場景啟動均通過；不是宣稱單次完整 runner 全綠。RV 檢查點測試原本寫死 v5 的預期已更新為 v6；一次戶外測試的 runner 因並行程序占用 main-scene.log 而失敗，已單獨重跑通過。原始日誌位於 `.godot/minor-full-suite*.log`、`.godot/minor-remaining-final.log`、`.godot/final-test_*.log`、`.godot/test-logs/`。文件相對連結與 `git diff --check` 通過。

## 畫面與實機

- 展示場產生並檢視全部 18 套畫面；另透過 computer-use 實際切換佈局與玩家視角，確認操作有效。原圖為 `.godot/minor-captures/00.png`–`17.png`，版本化 [18 套總覽](images/2026-09-26-minor-pois.jpg)。金屬使用專案既有磨損漆材質。
- 正式 seed 0／cell 0：左側、彎道、公路局部坡度約 -1.63%；seed 1／cell 0：右側、約 +1.69%；seed 2／cell 0：左側、約 -1.69%，場址橫跨 900 m 邊界。三處已目視確認輪胎驅動進場及倒車退出；更新後的回放再驗證回到公路並前進 40 m，三處 headless 均通過。
- 正式 seed 4／cell 2：右側、約 -7.16%。初版持續倒爬上坡公路的回放失敗；改為倒回公路後換前進檔離場，headless 與正式視窗目視回放均通過（[正式道路畫面](images/2026-09-26-minor-poi-production.jpg)）。未修改正式 RV 操控或物理參數。初版小範圍迴轉也未通過，因此測試場採沿來路倒車，不要求在 12 m 寬停車區迴轉。

## 效能抽樣

`scripts/profile_minor_streaming.gd`，seed 0、bands 4／5／6，以相同工具比較 v5 與 v6，分段建立且不生成 actor。新版本 seed 包含版本號，兩組植被與場址內容不完全相同；這是成本抽樣，不能當成純演算法 A/B。

| 版本 | 各帶 build_ms | 各帶 max_slice_ms |
|---|---|---|
| v5 | 441.6 / 412.1 / 471.9 | 33.4 / 33.4 / 35.4 |
| v6 | 588.5 / 584.8 / 510.1 | 39.3 / 86.0 / 34.8 |

場址查詢已加上最多 256 筆的縱向快取，避免每個地形 X 取樣重複規劃同一列。v6 仍有較高生成成本及單次切片峰值，未宣稱達到 4 ms 切片預算或消除卡頓。上述抽樣與其他驗證並行，非獨占機器基準。

## 限制

30–90 秒為探索設計目標，尚未做玩家群體時間或長局經濟平衡測量。場景道具是靜態造景；未增加開箱／修車／事件。未測翻車、大量怪物追逐、所有自訂道路參數與長時往返。場址外的普通散落物仍沿用現有清理規則。
