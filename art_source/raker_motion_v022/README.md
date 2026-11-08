# Raker v022 動作修整

[可編輯來源](raker_motion_v022.blend) · [正式 GLB](../../assets/models/raker/raker.glb) · [播放控制](../../enemies/raker_visual.gd)

Blender 5.2.3 LTS，場景 `RAKER_MOTION_V022`，物件 `Motion022_Rig`／`Motion022_Mesh`。從 [v021](../monster_refined_v021/README.md) 複製獨立骨架、網格與動作，保留原來源。54 變形骨、rest pose、蒙皮及貼圖不變；60 fps、41 個 NLA track。開啟後預覽 walk；切換 action 前保持所有 NLA track 靜音，並使用對應 action slot。

這次更新九段：

- idle／crouch_idle：較小的骨盆起伏、胸背呼吸、肩膀與腕部延遲，避免全身同步上下蹲。
- walk／chase／sprint／crouch_walk：承重側移、肩髖反向轉動、不同擺腿時間、足底離地後才轉踝；支撐期腳掌等速向後移動。兩節腿 IK 在製作時求解後烘焙，執行期不新增求解器。
- attack_left／attack_right／crouch_attack：壓低蓄力、髖部帶動揮擊、收勢回穩；站立動畫首尾與駝背待機一致。站立接觸時刻 0.72 秒、低姿態 0.60 秒、全段 1.2 秒。

步態原始設計速度為 walk 1.13、chase 2.3、sprint 6.0、crouch_walk 0.4 m/s；正式 Model 放大 1.2 倍後，播放控制同步按比例換算。左腳擺動中心在相位 0、右腳在 0.5，較快步態縮短支撐期；跨步態混合沿用相位傳遞。

## 匯出

選取骨架與蒙皮，暫時命名 `Raker_Rig`／`Raker_Mesh`；清除 active action 並開啟 NLA tracks。使用 glTF Binary、Selected Objects、Active Scene、NLA Tracks、Force Sampling、Deformation Bones、Y-up、無 vertex color。匯出完成後恢復製作物件名及預覽 action。貼圖已內嵌來源。

正式資產只替換九段動畫：按骨名將匯出 channel 映射到原 GLB node，複製 animation sampler、accessor 與 bufferView 資料。保留原 nodes／meshes／skins／materials／images 和另 32 段動畫，因此沒有重新匯出網格造成的外觀或綁定差異。Godot 仍沿用既有 30 fps 匯入設定。製作、匯出與檢查中間檔位於 gitignored `.godot/raker-motion/`。

## 2026-11-08 本輪檢查

- 逐一核對九段匯出時長、有限數值、root 無漂移、循環首尾一致；另 32 段動畫與原網格、骨架、蒙皮、材質及貼圖資料完全保留。
- Blender 九段每個整數影格檢查變形後網格：走跑腳底最低約 +0.16 mm；其他片段最低誤差小於 0.1 mm。三段低姿態最大高度 1.508 m，乘 1.2 後約 1.810 m，低於 1.85 m 碰撞淨空。
- Godot 匯入及 `scripts/test.ps1 -TestFilter test_raker_grab.gd` 通過，包含抓咬、輸入／所有權清理及新增低速步頻、狂奔遲滯、步態相位與獨立動畫資源檢查。
- 平面動畫展示使用正式 Raker 場景與遊戲渲染；屬動畫檢視，不代表完整 AI 導航、坡地、急轉、攀車、車輪驅動或群怪驗收。未新增地形腳掌 IK，也未窮舉所有跨動畫混合下的自交。
