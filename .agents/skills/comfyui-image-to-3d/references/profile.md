# 生成設定

腳本使用[固定 graph](../assets/trellis-single-1024-50k.json)，只替換圖片與輸出 prefix；調參用原生 graph/API。

| 項目 | 設定 |
|---|---|
| 模型 | TRELLIS.2 INT8、shape／texture VAE BF16、DINOv3 |
| 輸入 | 1024、alpha、pad 1.0、seed 42 |
| SS | 12 steps、CFG 7.5、shift 5、rescale 0.7 |
| Shape | 20 steps、CFG 7.5、rescale 0.5 |
| Upsample | 12 steps、CFG 7.5 |
| Texture | 12 steps、CFG 1、1024 貼圖 |
| Remesh | resolution 192、smooth_iters 2、project_back 0 |
| 降面 | midpoint、目標 50,000 面，實際面數另查 |

歷史環境：ComfyUI 0.38.0（`f1072eb`）、RTX 5070 Ti 16 GB。其他環境先跑節點／權重 preflight。

TRELLIS.2 與 Pixal3D 的 conditioning 不同，不能只換 checkpoint。mesh-input 材質生成尚未在本地實作；LOD 與遊戲效能另驗證。

## 歷史驗證

2026-10-05 床樣本成功生成 49,916 面，但比例與結構未驗收，研究素材未附帶。當時 validator、8 項 client 測試、HTTP 收檔／SHA、Godot 五視角渲染與錯誤 pose 拒收通過；submit 為 mock 測試。

歷史結果不代表本次驗證。後續工具檢查見[工作流驗證](../../../../docs/validation/2026-10-06-image-to-3d-workflow.md)，減面結果見[降面](decimation.md)。
