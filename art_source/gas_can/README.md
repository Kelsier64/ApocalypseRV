# 汽油罐：滿／空共用外觀

2026-10-09：正式資產 `assets/models/gas_can/gas_can.glb`，8,280 三角面、8,777 頂點、1 個 mesh／材質、3 張內嵌 1024² PNG。滿／空罐共用形狀，以既有名稱及物品資料區分。

尺寸 X×Y×Z = 0.39759523 × 0.84584963 × 0.82353514 m；GLB 包圍盒中心原點、+Y 向上、寬面正面 +X、厚度 X、提把長度 Z。場景原有 `(0.0022521876, -0.028735355, -0.0045410395)` 只留在 `gas_can` 實例位置，不烘入 GLB。提把／封閉蓋在包圍盒內；提把孔是貫通幾何，沒有液面、rig 或動畫。

`editable/gas_can.gltf`＋BIN＋PNG 可匯入 Blender 編輯；`raw.glb` 保留本次 TRELLIS.2 生成 bytes。`reference.png`、`reference_prompt.txt`、`conditioning.png`、`prompt.json` 與 `generation.json` 記錄來源。使用內建 imagegen 生成全新參考圖，沒有使用授權未核實的收存模型，也未覆寫原件。

`refinement.json` 記錄 raw Y 軸 +90° 旋轉、尺寸校正、切線修復與 gltfpack 1.3 參數。0.01 誤差上限的兩個候選停在約 11k；選 0.02 上限的 8,280 面版本。對照材質／灰模、原 up 與正面校正的六視角後，提把孔、蓋與壓紋可讀，三張貼圖 bytes 完全保留。預算以 .85 m、可近看的共用道具先取約 8k／10k 上限；沒有量測多罐 FPS，不把減面等同效能測試。

重建需要現有 Python／numpy 和 **gltfpack 1.3**，在專案根執行；輸出必須是不存在的新資料夾，不會覆寫手改 glTF 或正式 GLB。

```powershell
python -B art_source/gas_can/rebuild.py --gltfpack '.godot/gltfpack-1.3/bin/gltfpack.exe' --output '.godot/art-work/gas_can/rebuild-new'
python -B art_source/gas_can/audit_geometry.py assets/models/gas_can/gas_can.glb .godot/art-work/gas_can/geometry-check.json
godot --path . --script res://art_source/gas_can/preview.gd -- .godot/art-work/gas_can/context-new
```

PATH 的 python 在本機是無法啟動的 Windows 別名；實測使用 `load_workspace_dependencies` 回傳的 Codex bundled Python 完整路徑。

兩個正式場景保留原 BoxMesh／材質，`GasCanGraybox` 隱藏；`graybox/` 保存交付前的兩個原場景 bytes。還原時切換 `gas_can`／灰盒顯示，或使用來源備份；不要改動碰撞或把局部位移再加到模型。

驗證見 `validation/geometry.json`、`context.json`、`behavior.json`、`checkpoint.json`、`review.json` 與 `six_views.png`／`full_empty_context.png`。`preview.gd` 實例化正式道具與玩家並檢查尺寸／位移／碰撞射線。七項行為回歸與主場景 smoke 已通過；新增加油生成空罐後的磁碟序列化、重新持握／丟棄及滿空罐持物尺寸連續性、完整世界檢查點保存／重建後的場景路徑、ID、品質與共享模型覆蓋。

限制：原生成網格有非流形拓樸，減面版本在 1 µm 位置合併診斷下有 1,234 條非流形邊、221 組重複幾何三角形餘項；沒有宣稱封閉流形或重新拓樸。渲染驗收未見破洞／明顯閃爍，物理使用既有獨立盒碰撞。背面／底部由單圖推測；玩家持物位置沿用既有場景，近景很靠近鏡頭。

首次 Skill 實測時 `collect` 缺少 NORMAL／UV／TANGENT 與零長切線檢查；後續已依使用者要求補上有限值／數量驗證及方向異常回報，11 項離線測試通過。拓樸仍另行檢查；原 GLB 的 4 個零切線由 `refine.py` 在副本依 UV 鄰面修復。完整問題與環境排查見 `docs/validation/2026-10-09-gas-can-skills.md`。完整 job、history、所有候選與批次渲染留在已忽略的 `.godot/art-work/gas_can/20261009-01/`。
