# 避難所原生建築與部件需求修正

日期：2026-10-01。接續 [第一次擴建紀錄](2026-10-01-shelter-expansion.md)；該紀錄的 90 項測試屬前次執行，本次結果另記於下方。未使用子代理。

## 修正

- 撤回整棟 `starting-shelter-exterior` request。建築本體直接製作，不再等待外殼 GLB；建模說明明定 requests 僅限家具、道具、設備與獨立建築部件。
- 原生 `facade.tscn` 完成混凝土基座、立柱、屋頂金屬收邊、漆帶、四組鏽蝕封閉窗板與軍用編號。沿用現有材質，不重製素材，不增加可探索空間。
- 只保留獨立 [屋頂通風機組](../modeling/requests/shelter-roof-air-handler/shelter-roof-air-handler.md) 和 [屋頂過濾設備組](../modeling/requests/shelter-roof-filter-bank/shelter-roof-filter-bank.md) 的灰盒與 request；廢車及既有設備需求保留。
- 本輪沒有改動碰撞、导航、地形、車庫門、物資與保存程式。原建築尺寸與動線維持不變。

## 本輪檢查

- 統一 runner：`-TestFilter 'test_poi_definitions.gd,test_starting_shelter_terrain.gd' -Smoke`，資產匯入、兩項測試、正式主場景就緒與玩家移動全部通過，退出碼 0。日誌：`.godot/test-logs/20261001-192217-570-selected-33992/`。僅外觀與文件修改，沒有重跑完整行為測試。
- Forward+ 實機檢視：08:00 陰天外觀視角能辨認立柱、漆帶、封閉窗板與左右軍用標記，中央車庫及前庭保持暢通；屋頂兩台設備仍是待替換灰盒。日誌 `.godot/shelter-native-art-visual.log`。
- 文件相對連結與 `git diff --check` 於本輪完成時檢查；不把前次完整回歸算作本輪結果。
- 本輪 F2 實機輪驅回放再次通過：22.9 秒出庫、轉上公路並永久封門，HUD 與日誌均顯示 PASS。已關閉自己啟動的遊戲視窗，未操作或關閉 Godot 編輯器。
