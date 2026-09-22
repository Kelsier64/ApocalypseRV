# 怪物 GLB 試接

來源：`C:/Users/evan4/Projects/3d/exports/godot/monster_export_test.glb`，2026-09-22 複製；來源檔未修改。

SHA-256：`7B50DED7AD30BB9F7568E5C2531378A1FBE273B64722AA17BEAA50CA6CDBC2A0`。

- 1 個蒙皮網格、45 根變形骨、2 個材質、3,146 三角面；無 UV 貼圖。
- 來源高度 2.18 m、正面 +Z、腳底原點。Godot 匯入保留原始尺寸與骨架。
- [正式怪物場景](../../../enemies/zombie.tscn) 的 `BodyMesh/Model` 轉 Y 180°，等比例縮放 `1.5 / 2.18`；BodyMesh 上移 0.25 m 對齊原膠囊底部。碰撞、生命、導航與攀爬參數不改。
- [外觀腳本](../../../enemies/monster_model_visual.gd) 複製 `TEST_InPlace` 為循環播放的預覽動畫；受傷使用每個怪物獨立的材質 overlay，保留匯入材質。舊膠囊手臂不再疊加到模型上，掛車音效保留。
- `TEST_RootMotion` 保留匯入但不在遊戲播放，避免與 AI 位移重複套用。其 root 位置資料仍保留 +Z 1 m；尚未接入 root-motion extraction。
- 這是模型試接，尚無正式待機／行走／攻擊／攀爬／死亡片段。目前所有狀態播放原地測試姿態，因此有滑步及動作不符情境的限制；死亡沿用縮小消失。
- 保留原膠囊碰撞，手臂與細長四肢不逐部位命中，可能與近牆／攀爬表面穿插。若要使用來源 2.18 m 尺寸，需另驗收碰撞、車內高度與攀爬幾何。

[近距離預覽](../../../tests/monster_model_playground.tscn)：正式怪物追近玩家，F6 扣怪物 5 HP、R 重設；F3／F4 沿用追擊場的牆壁檢查。

[本次驗收與已知問題](../../../docs/validation/2026-09-22-monster-model.md)。
