# Raker v023 嘴部重建與抓咬動作

[可編輯來源](raker_motion_v023.blend) · [正式 GLB](../../assets/models/raker/raker.glb) · [抓咬時序](../../enemies/raker_grab.gd) · [執行期姿勢](../../enemies/raker_pose_modifier.gd)

Blender 5.2.3 LTS，場景 `RAKER_MOTION_V023`，物件 `Motion023_Rig`／`Motion023_Mesh`。由 [v022](../raker_motion_v022/README.md) 來源以腳本重建，不手動修改：骨架、rest pose、身體與手部貼圖、另外 23 段動畫沿用 v022。

## 建置

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background art_source/raker_motion_v022/raker_motion_v022.blend --python art_source/raker_motion_v023/build.py
```

[build.py](build.py) 依序重建嘴部、重做 18 段抓咬片段、逐幀檢查幾何、匯出完整 GLB、寫出本資料夾的 `.blend`，並覆蓋正式 GLB。加 `-- --no-install` 只產生來源與 `.godot/raker-motion-v023/` 下的匯出和 `build-report.json`，不動正式資產。建置後執行 `scripts/test.ps1 -TestFilter test_raker_grab.gd` 重新匯入並驗證。

正式 GLB 是完整重新匯出（網格已變）。匯出時把內嵌圖片改回 `raker_albedo_2k`／`hand_albedo`，Godot 抽出的貼圖檔名因此不變；並核對動畫名稱集合、54 個關節名稱與材質順序和前一版一致。

## 嘴部

[build_mouth.py](build_mouth.py) 移除 v018 的口腔與 18 顆圓錐牙，然後：

- 把嘴裂沿原唇面（z = 2.013，執行期嘴部錨點所在）向後切到臉頰，嘴角由 y −0.158 移到約 −0.090。
- 嘴唇自牙列後縮（上 5 mm、下 7.8 mm，向嘴角漸收並帶不規則邊緣），閉嘴時露出上下交錯的針狀牙。
- 重建牙齦、上顎、口底、喉部與舌頭；上下各約 32 顆牙沿牙齦交錯排列，長度與傾斜隨機（固定種子）。
- 下顎權重重新求解：顱骨與鼻吻固定為 0、下巴與張開的下唇固定為 1，其間沿網格鬆弛，臉頰和下頜下方因此平滑拉伸。口底與舌頭跟隨下頜下方皮膚的權重，張嘴時不穿出。

口腔與牙齒沿用原材質槽（`Raker018_OralCavity`／`Raker018_InternalTeeth`），貼圖改為腳本產生的色階 `Raker023_MouthLining`／`Raker023_Teeth`。

## 抓咬片段

[author_grab.py](author_grab.py) 以 v022 片段的手臂與手指姿勢為底，疊加下顎、骨盆、脊椎、肩與頭部動作，雙腳以兩節 IK 釘在原位後烘焙；60 fps。

| 片段 | 秒 | 內容 |
| --- | ---: | --- |
| reach | 0.6 | 壓低前探、微張嘴；執行期依伸手時間加速 |
| hold | 1.0 | 雙腳站穩，三次往後坐、聳肩的拉扯，下顎反覆咬合；最後約 0.3 秒後仰、嘴張到最大 |
| bite | 0.667 | 前撲、咬合，之後三次漸強的猛拽：身體往後坐、聳肩、咬緊；頭部翻扭由執行期解算 |
| release | 0.6 | 扯離、甩頭、兩次吞嚥後回到待機姿勢 |
| escape | 1.0 | 後仰踉蹌、右腳後撤一步、張嘴嘶吼後回穩 |
| miss | 0.45 | 撲空前傾、空咬後回穩 |

`stand`／`low`／`seat` 三種姿勢共用同一組曲線；蹲姿振幅為 0.6 倍，且不上升、少後仰。

`BITE_CONTACT`、`BITE_TEAR`、`THRASH_CYCLES`、`HOLD_TUGS`、`HOLD_TUG_ATTACK`、`HOLD_TUG_RELEASE` 與 [raker_grab.gd](../../enemies/raker_grab.gd) 的同名常數必須一致，`hold_tug`／`yank`／`thrash` 也與其同名函式對應：執行期拖動受害者和翻扭頭部，片段只在同一組節拍上讓身體往後出力，骨盆不左右擺。`test_raker_grab.gd` 會檢查片段長度涵蓋各階段，以及下顎在蓄力時張開、在咬合時刻收緊。

執行期仍由 `raker_pose_modifier.gd` 解算臉部朝向、咬合位置和抓握的雙臂；片段中的頭部動作只在扯離與掙脫時顯示（此時追視權重暫時降為 0）。

## 檢查範圍

建置時逐幀檢查 18 段：腳底不低於地面、蹲姿與座位片段最高點不超過蹲姿淨空或來源片段加 4 cm（座位片段的手肘原本就高於膠囊，執行期會重新解算手臂）。結果在 `.godot/raker-motion-v023/build-report.json`。

未做：v021 的身體自交、牙齒互穿與閉嘴遮齒掃描沒有對新嘴部重跑（新設計閉嘴時本來就露齒）；任意跨動畫混合下的自交未窮舉。
