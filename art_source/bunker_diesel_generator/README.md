# Bunker diesel generator

2026-10-07 製作，替換 [指定 wrapper](../../world/poi_kit/furniture/bunker/diesel_generator_graybox.tscn) 的 `Visuals/Model`。主機長軸 X、服務面 +Z、原點底部中心；靜態資產。3.20 W × 1.70 H × 1.20 D m 是使用者設計目標，已將完成候選校正到此包圍尺寸；不是從灰盒推算成品尺寸。

- [遊戲 GLB 與貼圖](../../assets/models/bunker_diesel_generator/README.md)：19,968 三角形，20,921 頂點，單一 mesh／材質，三張 1024² PNG。
- [可編輯 glTF](editable/bunker_diesel_generator.gltf) 配套 `.bin` 和三張 PNG，可直接匯入 Blender 或其他 glTF 編輯器；本輪沒有製作 `.blend`。
- [原始生成 GLB](run_01/raw.glb) 未改動；`run_01/` 保存 reference、conditioning、完整 prompt／history、job／result 與 SHA。
- [重建腳本](refine.py) 與 [修整參數](refinement.json)：預設從所選降面候選重建交付；`--high` 只重建高模基準，不覆蓋遊戲模型。
- [透明參考圖](reference.png) 使用內建 imagegen；完整提示詞在 [reference_prompt.txt](reference_prompt.txt)，沒有使用 API CLI fallback。
- [降面比較](review_reductions/review.json)、[最終十二張檢查圖與人工結論](review_reduced_final/review.json)、[正式電力廳尺寸／碰撞檢查](in_context/validation.json)、[交付檢查](validation/delivery-reduced-checks.json)、[本輪完整驗證](../../docs/validation/2026-10-07-bunker-diesel-generator-skills.md)。

## 製作與重建

本機 ComfyUI 0.38.0、TRELLIS.2 INT8、單圖 1024、seed 42、graph 目標 50k；prompt ID `f32e14f8-54ef-44cc-95f6-c3bd2320904e`。使用專案 [comfyui skill](../../.agents/skills/comfyui-image-to-3d/SKILL.md) 及 [3D scene skill](../../.agents/skills/apocalypse-rv-3d-scenes/SKILL.md)。來源為本輪 AI 生成；未使用外部模型或宣稱第三方素材授權。

原始 GLB 主軸 Z、服務面 +X，Y-up。先繞 Y -90°，再按完成網格的實測 AABB 做各軸尺寸校正與底部中心位移。旋轉後來源尺寸約 1.009003 × 0.583015 × 0.403473（生成單位）；比例 X/Y/Z = 3.171447 / 2.915877 / 2.974179，已記錄而非當作均勻縮放。此高模保存在 [fitted_49k/source.glb](fitted_49k/source.glb)，原修整記錄在 [refinement_original.json](fitted_49k/refinement_original.json)。

初次交付未嘗試降面，使用者指出後補做。以這個 3.2 m、可近距離觀看的固定大型設備先試約 20k；保守 `simplify.mjs` 受 UV／邊界／誤差限制只能到 47,063。再用官方 gltfpack 1.3 的有界 `-sp -sv -se 0.01`：40% 候選 19,968 面；20% 候選只降到 15,657 面，未達約 10k 目標。六方向共 36 張同基準取景比較後選 19,968，較低版本的排氣口及小輪廓損失較明顯。這是外觀與成本取捨，沒有量測 FPS。[降面參數與來源](reduction.json)保存命令、版本及 SHA。

gltfpack 改變拓樸、頂點及 UV 屬性，三張圖片 bytes 保持相同。所選候選尺寸略縮，再做 X/Y/Z = 1.000534 / 1.003767 / 1.002544 的微調及底部中心位移；反轉置法線、正交化切線烘入網格，這次 fit 保留降面後的索引／UV。[verify_delivery.py](verify_delivery.py)核對原件、圖片、有限屬性、單位法線／正交切線、editable 及原場景節點資料。

```powershell
# Python／Node／gltfpack 換成實際執行檔；本輪 gltfpack 位於忽略的 .godot/gltfpack-1.3/bin/。
python art_source/bunker_diesel_generator/refine.py --high
gltfpack -i art_source/bunker_diesel_generator/fitted_49k/source.glb -o art_source/bunker_diesel_generator/gltfpack_20k/candidate.glb -si 0.4 -se 0.01 -sp -sv -noq -kn -km -r art_source/bunker_diesel_generator/gltfpack_20k/report.json
python art_source/bunker_diesel_generator/refine.py

# 從專案根目錄啟動正式房間檢查；F2 循環近景／遠景／正式手電筒光束，Esc 關閉。
godot --path . --resolution 1280x720 --log-file .godot/diesel-generator-manual.log --script res://art_source/bunker_diesel_generator/preview.gd

# 保存三張圖並結束，驗證結果寫 in_context/validation.json。
godot --path . --resolution 1280x720 --log-file .godot/diesel-generator-capture.log --script res://art_source/bunker_diesel_generator/preview.gd -- --capture
```

重建會覆蓋對應輸出，修改前另存；手動編輯 glTF 後應直接匯出候選，不要再以腳本覆蓋編輯成果。raw 原件永不覆寫。比較腳本 [compare_reductions.py](compare_reductions.py)使用 skill renderer 的同一來源基準相機，輸出需為新資料夾；`review.py --candidate` 的嚴格頂點 mapping 檢查不適用 gltfpack `-sv`。Godot 最終包圍尺寸實測約 3.20000005 × 1.70000005 × 1.20000005 m，最低 Y = 0；檢查容差 0.002 m。

`python -B art_source/bunker_diesel_generator/verify_delivery.py` 檢查目前交付資料與保存的歷史驗證，不依賴 `.godot` cache 或目前 Git HEAD。原 wrapper 基準保存在 [wrapper_original.tscn](validation/wrapper_original.tscn)，來源 commit／SHA 見 [wrapper_baseline.json](validation/wrapper_baseline.json)。新的行為測試仍需另跑 `scripts/test.ps1`，不能把保存的 PASS 當成新執行結果。

## 已知限制

皮帶罩網孔主要是貼圖／法線凹凸，並非逐孔開放幾何；局部機件融合、邊緣略圓，未見的一側有生成的近似／重複細節，底板為簡化平面。此資產用於固定遠近景設備，不含可動機械、rig 或精密接頭。原廠 wrapper 整體盒碰撞維持不變，並未改成貼合各機件的碰撞。多台同屏 FPS 沒有量測；Godot 匯入保留預設自動 LOD。

原始 `review_raw` 記錄沙箱錯誤，`review_raw_native` 記錄舊版 clay 的過曝，`review_lighting*` 保留修燈比較。`review_final` 與 `fitted_49k/in_context` 是初次 49k 交付；現在採用 `review_reduced_final`、`in_context` 與 `validation/*reduced*` 作為最終證據，舊驗證結果保留且不可混用 SHA。
