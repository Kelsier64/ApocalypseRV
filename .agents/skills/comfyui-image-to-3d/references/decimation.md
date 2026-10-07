# 降面

依模型尺寸、觀看距離、同屏數量、輪廓與接口判斷遊戲面數預算，合適時試降面；若保留高面數，簡述其依據。模型已夠輕就不降。完整執行技術檢查與目視比較，保留原 GLB 和各候選供本機除錯；新建 `.godot/art-work/<asset>/<run>/candidates/` 存放候選、reports 與臨時檢查輸出。提交時只挑必要來源、正式資產和少量代表圖／摘要，不要求整套驗收產物入 Git，也不預設刪除本機工作資料。降面不能修直歪斜或補回缺件。

## 選方法

- **gltfpack／meshoptimizer**：先快速試減面，保留 UV／法線屬性與貼圖；`-sv` 會更新屬性值。切縫、拓樸與誤差限制可能阻止達標。
- **Blender 修整＋烘焙**：直接降面折疊、UV 碎裂或降不下去時，在副本修網格、減面、展 UV，再從高模烘焙材質。
- **重整結構**：voxel remesh 可處理部分封閉道具，但會柔化薄片、小孔與接口；必要時局部重建或改圖生成。

## gltfpack

用[官方工具](https://github.com/zeux/meshoptimizer/tree/v1.3/gltf)並記錄版本，無需新增全域安裝或遊戲依賴。v1.3 起點：

```powershell
$work = '.godot/art-work/example-asset/run-001'
New-Item -ItemType Directory -Force "$work/candidates/gltfpack-10-percent" | Out-Null
gltfpack -i "$work/generation/raw.glb" -o "$work/candidates/gltfpack-10-percent/candidate.glb" -si 0.1 -se 0.01 -sp -sv -noq -kn -km -r "$work/candidates/gltfpack-10-percent/report.json"
```

`-si` 是保留面數比例，`-se` 是演算法誤差上限。`-sp` 允許跨屬性切縫減面，`-sv` 更新頂點／屬性，可與不加兩者比較。`-noq` 關閉量化，`-kn -km` 保留命名節點／材質；壓縮支援另驗證。

查非空 mesh、有效索引／有限座標、實際面數、材質／貼圖及必要擴充，視需要查開放邊／非流形邊。宣稱貼圖完整保留時核對圖片 bytes／hash。退出碼 0 或檔案變小不代表合格或 FPS 提升；提高誤差或用 `-sa` 可能破壞貼圖、甚至移除全部幾何。

`review.py --candidate` 的完整性檢查只接受下述 `simplify.mjs` 的 metadata／頂點 mapping；不能用來驗證 `-sv` 更新屬性的 gltfpack 輸出。這類候選應在 Godot／Blender 用同一來源基準取景比較，另外核對幾何、材質與貼圖；不要為了通過檢查偽造 mapping 或宣稱原 UV／頂點 bytes 未變。

## simplify.mjs

指令見[操作](operations.md)。限制只適用這支腳本：

- meshoptimizer 1.3.0；CLI 必填面數，常用範例 20k。誤差上限 0.002，明確授權的 `--force-target` 改為 Infinity。
- normal 權重 1／1／1、UV 10／10、LockBorder；無語義接點鎖，Permissive／Prune／vertex update 關閉。
- 只接受單一無 transform mesh node、單一 TRIANGLES primitive、float32 POSITION／NORMAL／TEXCOORD_0／TANGENT、uint16／uint32 索引與內嵌圖片；不接受 animation、skin、morph、extensions 或額外 accessor。其他 GLB 換工具。
- 完整 tuple weld → 屬性感知化簡 → compact／重排 buffers；保留原 tuple、圖片 bytes、頂點 mapping 與來源 SHA，不移動頂點、重算法線或烘焙。原面數已達預算則保留原 bytes。
- 未達標寫 `TARGET_NOT_REACHED`／`target_reached:false` 並 exit 2。強制模式也可能被拓樸擋下，失敗不輸出候選；不當作通過，可另用副本修整。

LockBorder 只鎖拓樸邊界，不能辨識直柱或接點；輪廓、細桿與光影仍可能變差。誤差值不等於精確距離或外觀變化百分比。

## 歷史樣本

- **油桶（2026-10-06／07）**：499,846 面直接大幅減面造成折疊／UV 碎裂。Blender remesh＋烘焙得到接近原外觀的 3,000 面候選；gltfpack 保留外觀的候選約 22k 面，仍有非流形邊。激進設定曾造成貼圖錯亂或 0 面。此結果不代表所有模型。
- **床（2026-10-06）**：49,916 面在 0.002 上限只降到 42,786；授權強制後達 20,000，但仍有細節變化，原比例／橫桿問題未驗收。

油桶 Blender 起點：voxel 0.0035 m、Smart UV 66°／margin 0.012、Cycles selected-to-active、cage 0.015 m、ray 0.06 m、padding 12 px、三張 1024 圖。顏色用 DIFFUSE color-only，金屬粗糙度可用 emission 轉移（G roughness、B metallic）。數值隨尺寸調整，勿直接套薄片／細孔。

油桶只檢查過 Godot 單體顯示，尚未替換正式道具或驗證互動、多桶 FPS、主世界。詳見[Blender 紀錄](../../../../docs/validation/2026-10-06-oil-barrel-optimization.md)與[製作參數](../../../../art_source/oil_barrel/README.md)。
