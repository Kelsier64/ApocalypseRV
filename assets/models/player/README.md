# 玩家 Masked Survivor

目前為 2026-09-25 防水工作服／微蹲步態版，透過 Blender MCP 製作，並在 Godot 4.7.2 實際匯入測試。

- [完整 GLB](player_masked_survivor.glb)：1.60 m、12,066 三角面、55 骨、5 材質、10 主分件＋獨立白面具＋18 封口；無對講機。
- [可編輯來源、貼圖、動畫與切口表](../../../art_source/player_masked_survivor/README.md)。
- [九份斷肢 GLB](detached/) 只依賴自身骨鏈，上臂帶前臂與手，大腿帶小腿與腳。
- [獨立白面具](mask_default.glb)，100% 跟隨 head，可單獨隱藏／替換。
- 衣料為 PU 防水塗層方向，灰階貼圖乘 tint；袖肘、膝後與腰側新增皺褶。反光條、手套、靴、头套和白面具不受衣料換色影響。
- walk 為 1.2 秒原地微蹲步態，骨盆降低 6.7–7.3 cm，膝蓋持續彎曲；root 固定。其餘 10 段動畫保持獨立。
- GLB 正面 +Z／上 +Y；遊戲外觀包裝節點轉 Y 180°；Scale=1，沒有舊控制器 0.25 m 偏移。
- [匯入腳本](player_import.gd) 恢復 _loop 動畫名稱與循環旗標，由 .glb.import 指定。跨專案使用也需配置這些設定。

[本輪驗證](../../../docs/validation/2026-09-25-player-waterproof-walk.md)：GLB／Blender 檢查無失敗，統一 runner 的 import、test_player_model、main-scene 通過；已觀察 Godot Forward+ 的走路、側面、換色和低光材質。

資產只保留本目錄這一套正式路徑；revision7/8/9 等重複資產移至本機 art_source/player_masked_survivor/history，並排除 Git 與 Godot 匯入。PNG 與 .import 是 Godot 的實際貼圖依賴，不應全部刪掉。

尚未掛入 player/player.tscn。近景褲襠／衣領細節、極端抬臂變形、實際道具握點、RV／第一人稱校對與布娃娃遊戲規則仍需後續處理；12,066 面比原上限多 66 面，來自先前肩部變形環線，本輪未增加面數。
