# 單圖 → 3D 操作指南

兩套代理各自使用其 image-to-3D skill。共用的 [生成工具](../../scripts/comfyui-image-to-3d/scripts/generate.py) 提供 `preflight`、`run`、`status` 與 `wait`，可用 `--help` 查詢參數。

## 工具

| 工具 | 用途 | 位置 |
|---|---|---|
| ComfyUI＋TRELLIS.2 權重 | 生成 | `C:/Users/evan4/Apps`，由 `Pixal3D-API-v2/start.ps1` 啟動 |
| Python 3.11+、Pillow、numpy | skill 腳本 | 可直接用 `Apps/ComfyUI/pixal3d-runtime/.venv` |
| [Godot 4.7.2](https://godotengine.org/download/archive/) | 六視角檢查圖 | PATH 上的 `godot` |
| [gltfpack 1.3](https://github.com/zeux/meshoptimizer/releases/tag/v1.3) | 降面 | 解壓到忽略的 `.godot/gltfpack-1.3/bin/` |
| Blender（可選） | 修整、重新展 UV、烘焙 | 本機安裝 |

缺工具時停止並說明需要安裝什麼；不要改全域環境、不重裝服務或下載權重。

## 交付

- 每次工作用新的 `.godot/art-work/<asset>/<run>/`：job、history、候選、檢查圖、log 都留在這裡，不進 Git，也不預設清除。
- 進 Git 的只有：正式模型 `assets/models/<asset>/`、`art_source/<asset>/` 的參考圖、editable、`model_parameters.json`、簡短 README（來源、prompt ID、參數、面數、已知問題），必要時少量代表圖。
- 不要全域忽略 `art_source/` 或 `*.glb`／`*.png`；`.gitignore` 也不會移出已追蹤檔案。提交前看 `git diff --cached --stat` 確認檔案數與大小。
- 回報附物件名稱、階段、證據路徑、目前狀態與剩餘問題；未檢查的項目維持 UNKNOWN，不當作合格。

## 模型需求

需求只用於家具、道具、設備或獨立建築部件。整棟建築、外殼、牆體、地板、屋頂與場景配置直接在 Godot 場景裡做，不交給 image-to-3D。簡單物件直接完成，不寫需求。

複雜物件把需求寫在 `art_source/<asset>/request.md`，參考圖放同一個資料夾。場景要先能用時，先做灰盒、碰撞與互動，之後只替換外觀。大建築可以拆成能獨立製作與替換的部件，各寫一份；同一部件的重複實例共用一份。每個模型只維護一份需求，模型接入後刪除需求檔，留下資產 README。

需求包含：

- **要做什麼**：物件用途與需要製作的部分。
- **替換位置與尺寸方向**：場景或外觀節點、寬高深（公尺）、原點與正面朝向，註明是實測還是設計值。
- **外觀描述**：能直接用來製作參考圖的短描述，說明輪廓、配色、材質與必要細節，沿用專案的低彩度工業恐怖風格。
- **交付位置**：GLB 與貼圖放哪裡、可編輯來源放哪裡。只替換外觀，保留碰撞、互動與既有節點接口。
- **建築部件**另外寫所屬建築、相對父節點的位置與方向、接合尺寸及要保留的開口。
- **活動零件、插槽或骨架動畫**只在需要時寫名稱、位置、轉軸與動作要求；不預設生成結果已具備這些功能。
