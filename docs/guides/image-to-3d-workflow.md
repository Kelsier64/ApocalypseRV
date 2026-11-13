# 單圖 → 3D 操作指南

日常流程、指令與判斷都在 [image-to-3D skill](../../.claude/skills/comfyui-image-to-3d/SKILL.md)；本頁只補人工安裝與交付注意事項。

## 工具

| 工具 | 用途 | 位置 |
|---|---|---|
| ComfyUI＋TRELLIS.2 權重 | 生成 | `C:/Users/evan4/Apps`，由 `Pixal3D-API-v2/start.ps1` 啟動（見[本機操作](../../.claude/skills/comfyui-image-to-3d/references/operations.md)） |
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
