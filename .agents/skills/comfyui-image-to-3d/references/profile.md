# 生成設定

`generate.py` 使用[固定 graph](../assets/trellis-single-1024-50k.json)，只替換輸入圖片與輸出 prefix。要調參時直接用 ComfyUI 原生 graph／API，另存新 profile，不要改這份。

| 項目 | 設定 |
|---|---|
| 模型 | TRELLIS.2 INT8、shape／texture VAE BF16、DINOv3 |
| 輸入 | 1024、alpha、pad 1.0、seed 42 |
| SS | 12 steps、CFG 7.5、shift 5、rescale 0.7 |
| Shape | 20 steps、CFG 7.5、rescale 0.5 |
| Upsample | 12 steps、CFG 7.5 |
| Texture | 12 steps、CFG 1、1024 貼圖 |
| Remesh | resolution 192、smooth_iters 2、project_back 0 |
| 降面 | midpoint、目標 50,000 面（生成設定，不是遊戲預算） |

`preflight` 會確認 graph 的節點類別與四個權重檔都存在。環境：ComfyUI 0.38.0（`f1072eb`）、RTX 5070 Ti 16 GB；其他環境先跑 preflight。

TRELLIS.2 與 Pixal3D 的 conditioning 不同，不能只換 checkpoint。mesh-input 材質生成尚未在本地實作。歷史工具驗證見[工作流驗證](../../../../docs/validation/2026-10-06-image-to-3d-workflow.md)。
