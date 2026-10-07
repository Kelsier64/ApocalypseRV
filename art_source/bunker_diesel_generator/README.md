# Bunker diesel generator

固定 bunker 軍用柴油發電機，替換 [wrapper](../../world/poi_kit/furniture/bunker/diesel_generator_graybox.tscn) 的 `Visuals/Model`。設計尺寸 3.20 × 1.70 × 1.20 m，底部中心原點，長軸 X、服務面 +Z；19,968 三角面／20,921 頂點，單一 mesh／材質。[正式 GLB 與貼圖](../../assets/models/bunker_diesel_generator/README.md)。

## 必要來源與重建

- [原始模型](raw.glb) 保持生成 bytes；[原始參考圖](reference.png)、[實際 conditioning](conditioning.png)、[圖像提示詞](reference_prompt.txt)及[實際 graph](prompt.json)供追溯。
- [生成摘要](generation.json)：ComfyUI 0.38.0／TRELLIS.2 INT8、1024、seed 42、50k 生成設定、prompt ID 與來源 SHA。來源為本輪 AI 生成。
- [可編輯 glTF](editable/bunker_diesel_generator.gltf)含 `.bin` 及外部三張 PNG，可匯入 Blender；沒有 `.blend`。
- [重建腳本](refine.py)、[降面參數](reduction.json)、[尺寸修整參數](refinement.json)。raw 先繞 Y -90°，校正尺寸／原點，再以 gltfpack 1.3 有界降面；最後微調尺寸並修正法線／切線。

```powershell
# 使用現有 Python/Pillow 與官方 gltfpack 1.3；填入實際執行檔，不會自動安裝。
python -B art_source/bunker_diesel_generator/refine.py --gltfpack '<gltfpack.exe>'
python -B art_source/bunker_diesel_generator/verify_delivery.py

# 正式房間截圖與尺寸／碰撞檢查，輸出至已忽略的新 capture 資料夾。
godot --path . --resolution 1280x720 --log-file .godot/diesel-generator-capture.log --script res://art_source/bunker_diesel_generator/preview.gd -- --capture
```

重建只需要 Git 中的原始來源與現有 gltfpack 1.3，首次會在 `.godot/art-work/bunker_diesel_generator/rebuild/` 產生高模與降面候選，再更新正式 GLB／editable。`--high` 只建立忽略目錄中的高模基準。這次從空 rebuild 目錄重建，GLB SHA 與原交付完全相同；raw 永不覆寫。手動編輯 editable 後，應另存成果，避免重建覆蓋。

## 精簡驗證證據

[交付資料檢查](validation/delivery-checks.json)、[六方向人工 review 摘要](validation/review.json)、[正式房間尺寸／碰撞結果](validation/context.json)、[Godot selected＋smoke 結果](validation/runner-results.json)及[完整驗證報告](../../docs/validation/2026-10-07-bunker-diesel-generator-skills.md)。代表圖僅保留[降面比較](validation/reduction_comparison.png)與[正式房間手電筒畫面](validation/power_hall_flashlight.png)。

[verify_delivery.py](verify_delivery.py)查來源 SHA、圖片 bytes、有限屬性、單位法線／正交切線、設計尺寸、editable 與 GLB 一致性，以及[原 wrapper](validation/wrapper_original.tscn)的節點／碰撞保留；[基準來源](validation/wrapper_baseline.json)記錄原 commit／SHA。保存的行為結果是歷史證據，新的行為測試仍需另跑 `scripts/test.ps1`。

完整 job／history、所有候選、批次圖片、失敗輸出和舊日誌已移到本機忽略的 `.godot/art-work/bunker_diesel_generator/pr28-original/`，不屬於必要交付，也不影響重建／audit。後續 [preview.gd](preview.gd) 產物同樣輸出到新的忽略工作資料夾；只在需要更新代表證據時挑選檔案。

## 已知限制

皮帶罩網孔主要為貼圖／法線凹凸；部分小機件融合或略圓、背面近似／重複、底面簡化。靜態道具沒有 rig、機械動畫或精密接口。保留原整體盒碰撞；未量測多台同屏 FPS，Godot 匯入使用預設自動 LOD。
