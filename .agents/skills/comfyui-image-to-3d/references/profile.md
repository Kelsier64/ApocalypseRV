# 固定 profile 來源與邊界

graph 取自 2026-10-05 ApocalypseRV 實際執行的床研究，只將 LoadImage 與輸出 prefix 改成 runtime 欄位。技術生成成功，美術／介面尚未驗收。

- ComfyUI 0.38.0，git `f1072eb`；TRELLIS.2 INT8、shape／texture VAE BF16、DINOv3；RTX 5070 Ti 16 GB。其他 runtime 須通過節點／權重 preflight。
- seed 42；SS 12 steps、CFG 7.5、shift 5、rescale 0.7；shape 20 steps、CFG 7.5、rescale 0.5；upsample 12 steps、CFG 7.5；texture 12 steps、CFG 1。1024、alpha、pad 1.0。
- Remesh resolution 192、smooth_iters 2、project_back 0；midpoint decimation target 50,000；1024 材質貼圖。實測 49,916 面；目標面數不是保證面數。
- 實測 prompt `1b24d733-6807-44af-a80a-a1f7960370ce`，GLB SHA256 `9eff46de7573c67bddddd1a5968abfa4ef328ab04c2079f4c429f0f3313f5030`。
- 四柱中段約 0.73°～1.73°，只量測高度 40–65% 中段，不能證明全柱／橫桿／支撐面正確。高／長比 0.757，設計要求 0.925，仍未驗收。
- 此分支只收錄可重用工作流，不包含該床 GLB／圖片／研究輸出。原始證據保留在先前實驗 checkout；[後期降面方法](decimation.md)記錄同一 raw 的對照結果。

[官方單圖流程](https://docs.comfy.org/tutorials/3d/pixal3d)與[原生 conditioning](https://github.com/Comfy-Org/ComfyUI/blob/master/comfy_extras/nodes_trellis2.py)提供兩種模型路線。TRELLIS.2 與 Pixal3D 需不同 conditioning，不能只換 checkpoint。50k 是候選預算，遊戲 LOD／性能另驗證。

嚴格尺寸、直角與共平面可研究已驗收幾何＋材質生成；[官方 texturing pipeline](https://github.com/microsoft/TRELLIS.2/blob/main/trellis2/pipelines/trellis2_texturing.py)有 mesh 輸入，但本地尚未實作／測試，不是此 skill 已提供功能。

## 先前工具驗證（歷史紀錄）

2026-10-05：官方 skill validator 通過；8 項 client 行為測試通過（忙碌佇列、未知提交禁止重送、固定 graph／原圖保留、收檔不 POST、不接受其他 client 的 history、缺 conditioning、精確 reconcile、破損 GLB）。submit 的分支為 mock 測試，本次沒有重新提交 GPU 工作；固定 graph 的生成依據為上方先前實測。

實際 8000／8188 preflight、既有 50k GLB inspect、對原 prompt 的真正 HTTP collect 均成功，原始 SHA 相符並保持 ART_REVIEW_REQUIRED。Godot 4.7.2 五視角實際渲染 exit 0；非剛體 pose 測試 exit 1。這些只驗證工具，沒有把床改成美術驗收通過。

這些歷史結果不代替本分支新工具的檢查；目前驗證見[工作流驗證](../../../../docs/validation/2026-10-06-image-to-3d-workflow.md)。
