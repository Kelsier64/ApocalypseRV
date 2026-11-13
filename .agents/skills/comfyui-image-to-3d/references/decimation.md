# 降面

先訂預算再降：依尺寸、觀看距離、同屏數量、輪廓與接口判斷；模型已夠輕就不降，保留高面數時簡述理由。降面不能修直歪斜或補回缺件。保留 raw，候選放 `.godot/art-work/<asset>/<run>/`；只把正式資產、來源與精簡參數放進 Git。

## 選方法

| 方法 | 何時用 |
|---|---|
| gltfpack 1.3（`prepare_prop.py --ratio`） | 預設。保留 UV／法線與貼圖 bytes，快 |
| Blender 修整＋烘焙 | gltfpack 降不到預算、出現折疊或 UV／貼圖碎裂 |
| 局部重建／改圖重生 | 結構本身錯誤；voxel remesh 會柔化薄片、小孔與接口 |

## gltfpack

[官方 v1.3](https://github.com/zeux/meshoptimizer/releases/tag/v1.3) 放在忽略的 `.godot/gltfpack-1.3/bin/gltfpack.exe`，不是遊戲依賴。`prepare_prop.py` 使用 `-si <ratio> -se <error> -sp -sv -noq -kn -km`：

- `-si`：保留面數比例；`-se`：演算法誤差上限（不是公尺容差）。預設 0.025。
- `-sp -sv`：允許跨屬性切縫並更新頂點屬性；`-noq` 關量化；`-kn -km` 保留節點與材質。
- 誤差上限可能讓結果停在比例之上；看 `model_parameters.json` 的實際 `triangles`，不要宣稱已達標。提高 `-se` 或改用 `-sa` 可能破壞貼圖、甚至刪光幾何。

需要不經 `prepare_prop.py` 的獨立候選（與 raw 同座標系，可用 `review.py --candidate` 並排比較）：

```powershell
$gltfpack = '.godot/gltfpack-1.3/bin/gltfpack.exe'
New-Item -ItemType Directory -Force "$work/candidates" | Out-Null
& $gltfpack -i "$work/generation/raw.glb" -o "$work/candidates/r012.glb" -si 0.12 -se 0.025 -sp -sv -noq -kn -km
& $py "$skill/scripts/generate.py" inspect --glb "$work/candidates/r012.glb"
& $py "$skill/scripts/review.py" --source "$work/generation/raw.glb" --candidate "$work/candidates/r012.glb" --output "$work/reviews/r012"
```

exit 0 或檔案變小不代表合格。看灰模輪廓、細桿、孔洞與材質圖；宣稱貼圖完整保留時核對圖片 SHA（`prepare_prop.py` 自動核對）。

## Blender 修整＋烘焙

在副本 voxel remesh → 減面 → Smart UV → 從高模烘焙。油桶起點：voxel 0.0035 m、Smart UV 66°／margin 0.012、Cycles selected-to-active、cage 0.015 m、ray 0.06 m、padding 12 px、三張 1024 圖；顏色 DIFFUSE color-only，金屬／粗糙度用 emission 轉移（G roughness、B metallic）。數值隨尺寸調整，不要直接套薄片或細孔。詳見[油桶紀錄](../../../../docs/validation/2026-10-06-oil-barrel-optimization.md)。

## 實測參考

| 物件 | 結果 |
|---|---|
| 多數道具（food、service fan、air compressor、scavenge loot） | gltfpack ratio 0.06–0.12、error 0.025 → 約 5k–13k 面，貼圖 bytes 保留 |
| 油罐 0.85 m | ratio 0.12、error 0.02 → 8,280 面；error 0.01 停在約 11k |
| 柴油發電機 | ratio 0.4 → 19,968 面；0.2 只到 15,657（誤差上限擋住） |
| 油桶 499,846 面 | 直接大幅減面造成折疊／UV 碎裂；Blender remesh＋烘焙得到接近原外觀的 3,000 面 |

結果因模型而異，只作起點。
