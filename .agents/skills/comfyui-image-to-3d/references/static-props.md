# 靜態道具共用工具

`scripts/prepare_prop.py` 需要 numpy，離線操作，不提交 ComfyUI 工作。只接受單一無 transform mesh node、單一 indexed TRIANGLES primitive、float32 POSITION／NORMAL／TEXCOORD_0（可含 TANGENT）、內嵌 PNG；不支援 animation、skin、morph、extensions 或多材質拆 mesh。這些模型用其他工具，勿硬合併以通過檢查。

## 製作副本

先保留 wrapper 原始備份，輸出使用新的忽略資料夾。範例尺寸、朝向及面數是示例，須依需求決定：

```powershell
$skill = '.agents/skills/comfyui-image-to-3d'
$work = '.godot/art-work/example-asset/run-001'
Copy-Item 'world/poi_kit/furniture/bunker/switchgear_graybox.tscn' "$work/wrapper.before.tscn"
python "$skill/scripts/prepare_prop.py" prepare --source "$work/generation/raw.glb" --output "$work/prepared" --asset example_asset --size 1.2 2.35 0.72 --origin bottom-center --front +Z --rotation-y 0 --gltfpack '<gltfpack.exe>' --ratio 0.08 --error 0.025
```

- `--size` 是 X/Y/Z 公尺；`--origin center` 或 `bottom-center`。`--rotation-y` 是度數，在尺寸校正前套用。`--front` 只記錄預期朝向，工具不辨識正面，須目視確認。
- 不降面時省略 `--gltfpack`、`--ratio`。使用降面前讀[方法與限制](decimation.md)；工具採 `-sp -sv -noq -kn -km`，記錄實際版本／參數，不保證達到指定比例。`0.025` 是已有樣本用過的演算法誤差上限，非遊戲尺度公尺容差。
- 產出 fitted／reduced／final GLB、精簡參數及外部貼圖的 editable glTF/BIN；圖片 bytes 與 raw 相同，原檔不修改。法線以逆轉置校正，切線重新正交化；拓樸只計數回報，不自動修復。
- 原型與 final 的材質／素色多角度比較可沿用 `review.py --source`，gltfpack 結果不使用 `--candidate`。完成情境檢查仍由 agent 判斷；檔案成功輸出不代表美術驗收。

## 檢查後接入

只適用 `.tscn:Visuals/Model` 為 Node3D、尚未接入 Asset 的灰盒 wrapper；指定要隱藏的直接子節點。其他 wrapper 或既有正式資產直接編輯，不移動碰撞遷就外觀。

```powershell
python "$skill/scripts/prepare_prop.py" publish --prepared "$work/prepared" --scene 'world/poi_kit/furniture/bunker/switchgear_graybox.tscn' --expected-scene "$work/wrapper.before.tscn" --hide Blockout Panel Stencil
```

工具先比對 wrapper 備份與 final hash；保留原換行、Model 屬性、節點名稱及碰撞，只新增 GLB 子節點並隱藏指定灰盒。正式檔放 `assets/models/<asset>/`，可編輯來源與參數放 `art_source/<asset>/`；已有交付檔或場景同時被修改時停止。參考圖、生成來源資訊與精簡驗證摘要由 agent 補入來源目錄。Godot 匯入後確認實際尺寸、原點、朝向、所有使用處及相關行為；tool 不會自動將美術驗收標為通過。

工具改動時執行 `python "$skill/scripts/test_prepare_prop.py" -v`，測試使用 repo 的配電櫃 GLB，在暫存目錄檢查旋轉／非等比縮放、雙原點、法線／切線、貼圖與 editable 保全、場景屬性／碰撞保全及並行修改拒絕，不重新生成模型或修改正式場景。
