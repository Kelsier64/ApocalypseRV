# 野外廢棄庭院避難所

2026-10-22。新增 [L 形庭院場景](../../world/roadside_pois/courtyard_shelter.tscn) 與 [POI 定義](../../world/poi_definitions/courtyard_shelter.tres)，沿用目前分支。

- 北翼與西翼圍出庭院，沿用原民用避難所的混凝土、鏽蝕金屬及低解析風格，保留前後通路與分離的建築／家具／碰撞／出生標記。
- 僅在 OFF_ROAD 生成，直接步行探索。越野候選仍為 40% 地堡、20% 避難所、40% 營地／棚屋；避難所子池均分為 civilian_shelter 與 courtyard_shelter，各占全部候選 10%。實際接受率仍受地形及水域避讓影響。
- 生成身分更新為 v17，Checkpoint 外層仍為 v6；依目前政策舊世界需重新開局。道路 RNG 域沿用 v13，relief／dry-valley／flora 域沿用 v14，越野位置、物資及敵人等預設 RNG 域保留 v15；新增變體只使用原本獨立的 offroad_theme 流。
- 兩款避難所共用原 WalkInSites 首訪生成、卸載及回訪保存；沒有新增專屬保存格式。

## 本輪檢查

Forward+ 使用正式 seed 42、row 41、column 2 的場址，中心 (254.9396, 67.86921, -37422.64)，建立 248–250 三個地形區塊。固定日間預覽光照獨立於動態世界時鐘；檢查外觀、庭院、床區與北翼大廳四個視角，五張簡模床、長桌椅、補給架、混凝土水槽與排水溝、破頂及雨棚均可見。正式地形導航的庭院→北翼→後門及庭院→西翼床區路徑通過。場景使用 16 個網格批次、140 個碰撞形狀。

預覽腳本、日誌及四張圖片留在忽略目錄：`.godot/review_courtyard_shelter.gd`、`.godot/courtyard-review.log` 與 `.godot/courtyard-shelter-{exterior,court,beds,hall}.png`。這是渲染目視與導航檢查，未做鍵盤搜刮、夜間戰鬥或全種子驗收。

Godot 4.7.2 本輪匯入、`test_checkpoint_failures`、`test_streaming_generation` 與正式主場景 smoke 全部通過；日誌 `.godot/test-logs/20261022-105244-425-selected-31976/`，約 54 秒。擴充既有越野契約驗證兩款避難所的確定性生成、定義／界限、主要室內外導航、首訪不重複、卸載及掉落物回訪恢復；另保留自然地面串流接縫與 v15 RNG 域檢查。Checkpoint 拒絕舊生成 v16，接受當前 v17。未執行完整測試套件。
