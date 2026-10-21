# 野外廢棄民用避難所

2026-10-22。新增 [靜態場景](../../world/roadside_pois/civilian_shelter.tscn) 與 [POI 定義](../../world/poi_definitions/civilian_shelter.tres)，沿用目前分支。

- 主體約 18 × 13 m，另含前廊、退縮門廳、前後入口、六床休息區及共用補給區。窗洞深度、倒角收邊、樑柱、排水管、通風座、缺口女兒牆和破頂均為實際幾何；牆面局部剝落沿用既有凹陷水泥表面製作方式。
- 美術沿用冷灰水泥、土褐、鏽蝕和低解析表現；16 個材質網格批次、94 個靜態碰撞。家具依使用者要求暫留簡模，之後可替換 ComfyUI 資產；本輪未生成家具模型。
- 僅 OFF_ROAD、WALK_IN。候選比例為地堡 40%、民用避難所 20%、營地／棚屋 40%；實際生成仍需通過地形及道路避讓。首訪物資、敵人、卸載與重訪沿用 WalkInSites。
- 新局改為生成 v16，預設 RNG 保留 v15 的既有串流，地形／道路原有固定 RNG 域保持不變。Checkpoint 仍為 v6，拒絕生成 v15 存檔；依專案政策重新開局，不遷移舊世界。

本輪檢查使用 Godot 4.7.2。生成版本更新後，統一 runner 的 checkpoint_failures、streaming_generation、主場景 smoke 通過；紀錄 `.godot/test-logs/20261022-011456-175-selected-25512/`。之後依回饋擴建建築，最終 streaming_generation 再次通過（24.374 秒，匯入 5.529 秒），紀錄 `.godot/test-logs/20261022-013039-665-selected-18924/`。新增固定回歸涵蓋網格／94 個碰撞界限、物資保存界限，以及前門、床區、大廳、後門的直接人形導航路徑；沒有額外建立整組地形區塊。文件連結與 `git diff --check` 通過。

Forward+ 以 seed 42、row 13、column 2 的正式場址及三個地形區塊渲染，檢查外觀、入口、床區與破頂補給區，另補原生解析度的立面近景。放大後曾發現向內開的門片使床區導航斷開，改為向外開入退縮門廳；最終前門→大廳→床區→後門路徑可達，且檢查路徑長度以排除繞到建築外的替代路線。日誌 `.godot/shelter-review.log`、`.godot/shelter-detail-review.log` 與六張 `.godot/civilian-shelter-*.png` 均留在忽略目錄。這是渲染目視與導航檢查，未做鍵盤實機搜刮、夜間戰鬥或全種子驗收。
