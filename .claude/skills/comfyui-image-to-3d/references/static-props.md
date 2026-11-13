# 靜態道具工具 `prepare_prop.py`

離線工具（需 numpy），不提交 ComfyUI 工作、不修改原檔。只接受：單一無 transform 的 mesh node、單一 indexed TRIANGLES primitive、float32 POSITION／NORMAL／TEXCOORD_0（可含 TANGENT）、內嵌 PNG。animation、skin、morph、extensions、多材質模型改用 Blender，不要硬合併來通過檢查。

## prepare

```powershell
& $py "$skill/scripts/prepare_prop.py" prepare --source "$work/generation/raw.glb" --output "$work/prepared" `
  --asset <asset> --size 1.2 2.35 0.72 --origin bottom-center --front +Z --rotation-y 0 --ratio 0.12 --error 0.025
```

| 參數 | 說明 |
|---|---|
| `--size X Y Z` | 最終外框（公尺），逐軸縮放。要保比例就用同一倍率算三軸 |
| `--origin` | `bottom-center`（放地上）或 `center`（拾取物常用） |
| `--rotation-y` | 度數，縮放前套用。先看 raw 的 front 圖判斷 |
| `--front` | 只記錄預期正面，工具不會辨識，須目視確認 |
| `--ratio`、`--error` | gltfpack 降面；省略 `--ratio` 則不降面。`--gltfpack` 可指定執行檔 |

輸出到新資料夾：`fitted.glb`、`reduced.glb`、`final.glb`、`model_parameters.json`（尺寸、面數、拓樸計數、hash、生成來源）、`editable/`（外部貼圖的 glTF/BIN）。法線以逆轉置校正，塌陷切線會依 UV 重建並正交化；拓樸問題只計數、不修。圖片 bytes 與 raw 相同。

輸出後用 `review.py --source "$work/prepared/final.glb"` 再看一次；成功輸出不代表美術合格。

## 只調整整體大小

外形正確只是尺度不對時，不必重生。以角色與場景為基準等比縮放；Godot 剛體根節點 scale 保持 1，調視覺節點並同步碰撞尺寸與擺放高度，確認接地、拾取與手持。分開記錄 GLB 尺寸與場景最終尺寸。

## 檢查後接入

只用於 `Visuals/Model` 為 Node3D、尚未接入 `Asset` 的灰盒 wrapper。先備份 wrapper，`--hide` 列出要隱藏的灰盒直接子節點：

```powershell
Copy-Item '<wrapper>.tscn' "$work/wrapper.before.tscn"
& $py "$skill/scripts/prepare_prop.py" publish --prepared "$work/prepared" --scene '<wrapper>.tscn' `
  --expected-scene "$work/wrapper.before.tscn" --hide Blockout Panel
```

工具核對備份與 final hash，保留原換行、Model 屬性、節點名稱與碰撞，只新增 GLB 實例並隱藏灰盒。寫入 `assets/models/<asset>/<asset>.glb` 與 `art_source/<asset>/{editable/,model_parameters.json}`；交付檔已存在或場景被同時修改時停止。參考圖與 README 由 agent 補進 `art_source/<asset>/`。之後在 Godot 匯入並確認尺寸、原點、朝向、所有使用處與相關行為。

其他 wrapper 或已接入的正式資產直接編輯，不移動碰撞遷就外觀。
