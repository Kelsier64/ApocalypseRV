# 玩家模型 Godot 實機檢查（2026-09-24）

本頁保留修正前的觀察與證據；目前資產已更新，請先看[修正版 2 的修正與複查](2026-09-24-player-model-revision2.md)。

結論：**資產可以載入與播放，但近景外觀驗收未通過。** 自動結構檢查的 PASS 不代表蒙皮沒有穿模。這次沒有修改 Blender／GLB，也沒有接入正式玩家控制器。

## 實際執行

Godot 4.7.2 stable official、Forward+／Vulkan、RTX 4060 Laptop GPU。透過桌面操作選取獨立遊戲視窗，未操作原本開啟的 Godot 編輯器。測試後關閉本輪測試視窗。

[測試場](../../tests/player_model_playground.tscn) 直接實例化交付的 `assets/models/player/player_masked_survivor.glb`，以 AnimationPlayer 逐幀取樣播放匯入動畫，分離模式另載入九份獨立 GLB。不是 Blender 預覽圖。

```powershell
godot --path . --log-file .godot/player-model-inspection.log res://tests/player_model_playground.tscn
```

N／P 下一段／上一段；Space 暫停；左右鍵暫停逐格；R 還原 A-pose；V 循環正／側／背／斜角／左右手／頭部視角；T 換色；M 隱藏面具；D 循環九個分件；L 強制最高網格細節；F2 自動巡覽；Esc 關閉。可加 `-- --replay` 每四秒換動作；也可用 `-- --clip=sit_driver --view=4` 直接重現左手近景。分離模式預設中立姿勢，未模擬斷肢物理。

## 實際觀察

| 項目 | 結果 |
|---|---|
| 十一段具名動畫 | 逐項選取 idle、walk、jump、fall_loop、land、climb_loop、hang_idle、sit_driver、hold_small、carry_large、injured_idle，均顯示相應姿勢 |
| 手與對講機 | A-pose 與坐姿拇指位於正確側邊、坐姿拇指在上；沒有對講機。手腕／衣袖仍有下面列出的缺陷 |
| 換色 | T 切赭色後，軀幹、袖子、褲管一起變色；反光條、黑手套／靴、米色頭套、白面具保持固定色 |
| 面具 | 能獨立隱藏、恢復；隱藏後頭套仍完整 |
| 九個分件 | 左右肩、肘、髖、膝及頸均可切換，獨立資產可顯示；上臂攜帶前臂和手，大腿攜帶小腿和靴。畫面可見部分封口，未對每個封口的兩面做全角度驗收 |
| 日誌 | 兩次可見視窗執行無腳本錯誤／引擎 ERROR；保留原始日誌 |

## 未通過項目

1. **坐姿袖口露出紅色內部面**，左右手均能重現，手套與袖口交界有不自然的鋸齒狀輪廓。見[左手](../../art_source/player_masked_survivor/godot_review/11_left_hand_issue.png)、[右手](../../art_source/player_masked_survivor/godot_review/12_right_hand_issue.png)。
2. **hold_small 的另一隻手穿過袖子**，近景可見數個指尖穿出袖面。見[穿模畫面](../../art_source/player_masked_survivor/godot_review/13_hold_small_issue.png)。
3. **肩腋與肘部變形不自然**：攀爬／懸掛時肩腋出現尖銳折角，坐姿肘部鼓起；衣領與肩上也能看到細小暗縫。見[懸掛背面](../../art_source/player_masked_survivor/godot_review/09_hang_back.png)、[坐姿](../../art_source/player_masked_survivor/godot_review/10_sit_driver.png)。
4. 手掌、袖子、褲襠與口袋仍有明顯首版幾何感，衣褶不足，不能據此宣稱達到委託的近景美術品質。

切換 `Viewport.mesh_lod_threshold=0` 強制全細節後，坐姿袖口紅面和折角仍在，**不能靠關閉自動 LOD 解決**。見[全細節對照](../../art_source/player_masked_survivor/godot_review/29_no_lod_issue.png)。確切責任面、權重與袖口厚度需返回 Blender 排查，本輪沒有假定修好。

## 自動檢查（本輪重跑）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Godot 'C:/Users/evan4/AppData/Local/Programs/Godot/Godot.exe' -TestFilter test_player_model.gd
```

Import、test_player_model、main-scene 三項 PASS。模型測試：1.75 m、11,746 三角面、55 骨、29 Mesh、5 材質、11 段獨立動畫、519 個骨骼姿勢取樣、9 份獨立斷肢資產；failures 為空。[本輪 JSON](../../art_source/player_masked_survivor/godot_review/automated_asset_check.json)。headless import 的系統憑證警告依既有 runner 規則處理，與模型渲染無關。

這些檢查核對資源、尺寸、材質、骨骼有限數值與動畫旗標，**不檢測網格自交／袖口露出內部面**。本輪未重跑全部遊戲行為測試；主場景啟動通過也不代表此模型已掛到正式玩家。

## 證據與範圍

[29 張實機截圖及日誌](../../art_source/player_masked_survivor/godot_review/)，包含每段動作、九個分件、換色、面具隱藏及 LOD 對照。截圖是桌面測試視窗原始擷取。

未驗收實際方向盤／道具握點、RV 淨空、正式第一人稱視角、動畫混合、碰撞、物理骨、活體斷肢規則，以及完整逐面／逐幀自交。這些結果不得解讀成可直接投入正式遊戲的完成品。
