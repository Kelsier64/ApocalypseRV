# Raker v018：蹲姿抬頭、原生嘴縫與內藏牙齒

以 v017 檔內保留的 v016 網格重建嘴部，因此沒有沿用 v017 的外掛唇圈、牙齦和外露牙齒。原生面部接出三圈皮膚過渡與四圈口腔內壁，18 顆牙齒沿口內弧線排列。閉嘴時牙齒被皮膚遮住，張嘴才顯露。皮膚維持原有污垢貼圖，嘴邊 UV 具有面積，避免零面積 UV 拉成條紋；皮膚背面剔除，避免從口內看見下巴皮膚的背面。

- 場景 `MONSTER_REFINED_V018`；網格 `Refined018_Mesh`、骨架 `Refined018_Rig`。
- 中立身高 2.18 m、9,129 來源頂點、18,182 三角面、4 材質、46 變形骨、41 段動畫。
- 非咬擊片段下顎閉合。咬擊 0.045–0.22 s 漸開至 27°，保持至 0.285 s，0.38 s 完成快速咬合，0.40–0.53 s 有 2.5° 小幅回彈。
- 根骨不位移；遊戲的頭頸追視、接觸 IK 和貼臉脊椎修正位於 `enemies/raker_pose_modifier.gd`，不烘焙進動畫。

## 重建

在專案根目錄，以 Blender 5.2.2 LTS 執行：

```powershell
blender --background art_source/monster_refined_v017/monster_refined_v017.blend --python art_source/monster_refined_v018/build.py --python art_source/monster_refined_v018/finish.py
blender --background art_source/monster_refined_v018/monster_refined_v018.blend --python art_source/monster_refined_v018/audit.py
```

`build.py` 複製來源與動畫後重建；`finish.py` 只匯出新版所選模型／骨架，保持正式節點名稱；`render_review.py` 可重拍正面閉嘴／張嘴預覽。將 `raker_refined_v018.glb` 複製至 `assets/models/raker/raker.glb`，再執行匯入及 Raker 回歸。

## 驗證範圍

[validation.json](validation.json) 保存 41 段動畫逐影格檢查、根骨平移、下顎角度、牙齒碰撞及五方向遮齒射線。身體自交掃描排除嘴縫／口腔的刻意接觸區與牙根嵌入；射線取樣也不等於所有視角的逐像素保證。嘴部外觀另以 Blender 預覽與遊戲第一人稱檢查。

[本次遊戲驗收](../../docs/validation/2026-09-23-raker-v018.md)。歷史模型與場景保留；不覆蓋使用者已開啟而未儲存的 Blender 視窗。
