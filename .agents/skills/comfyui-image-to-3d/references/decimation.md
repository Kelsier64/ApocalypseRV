# 後期降面方法與限制

工具固定使用 [meshoptimizer v1.3 JavaScript simplifier](https://github.com/zeux/meshoptimizer/blob/v1.3/js/README.md#simplifier) 的 `simplifyWithAttributes`。以索引的 edge collapse 降低三角面數，成本包括幾何與 normal／UV 属性；這是近似混合誤差，不是精確毫米距離、表面 Hausdorff bound 或外觀變化百分比。

## 固定參數

| 參數 | 值／行為 |
|---|---|
| 版本 | meshoptimizer 1.3.0，輸出记录 module SHA |
| 目標 | 預設 20,000 三角面；request 指定時覆蓋 |
| relative error cap | 0.002；明確 `--force-target` 才用 Infinity |
| normal weights | 1、1、1 |
| UV weights | 10、10 |
| flags | LockBorder |
| vertex_lock | null；沒有語義柱腳或接點鎖 |
| Permissive／Prune／vertex update | 全部關閉 |
| texture rebake／axis scaling | 不執行 |

讀 GLB → 檢查固定 profile 格式 → 只 weld 完整相同 POSITION＋NORMAL＋UV＋TANGENT bytes → 一次屬性感知化簡 → compact 仍使用的原頂點 → 拷貝原 tuple／嵌入圖片 → 重排 bufferViews、accessors 與索引 → 新 GLB／mapping／摘要。每個輸出頂點可回溯原頂點索引；原檔 SHA 必須不變。原面數已符合預算時直接保留 GLB bytes。

[官方屬性感知化簡說明](https://github.com/zeux/meshoptimizer/blob/v1.3/README.md#attribute-aware-simplification)與[原始碼](https://github.com/zeux/meshoptimizer/blob/v1.3/src/simplifier.cpp)說明幾何／屬性成本及 flip 等約束。LockBorder 保留拓樸边界，並不是辨識／鎖住直柱、直角或語義接點。UV／法線 seams 仍會限制化簡。

## 強制模式

Infinity 只移除停止用的誤差上限，成本仍用于選擇 edge collapse。拓樸仍可阻止達標；腳本不再開 Permissive、不截掉 triangles 假達標。預設受限模式若沒達標會寫 `state:TARGET_NOT_REACHED`／`target_reached:false` 並 exit 2，呼叫 agent 必須停止；強制模式仍沒達標则停止且不輸出候選。

原頂點座標不移動，但連接關係減少，輪廓、薄桿、布料摺痕、UV插值與陰影仍可能變差。切線／法線是保留下來的原 tuple，沒有重計算，所以必須看實際 textured 視圖。降面不是矯正歪斜的方法。

## 格式邊界

只接受一個沒有 transform 的 mesh node、一個 TRIANGLES primitive、float32 POSITION／NORMAL／TEXCOORD_0／TANGENT、uint16／uint32 索引、嵌入圖片，無 animation／skin／morph／extensions／額外 accessor。這是固定 ComfyUI profile 的保守範圍。其他 GLB 停止並報告，不由 agent 自動轉檔改拓樸。

## 床樣本（歷史證據）

2026-10-06，原圖 TRELLIS 50k raw 為 49,916 三角面、37,823 vertices。預設 0.002 上限僅到 42,786 面；20k 目標不能達成。使用者指定不管誤差強制 20k 後得到 20,000 面、17,946 vertices，混合誤差 0.0095652，圖片 bytes／原 tuple 保持，但中段柱向近似最差約 3.01°。五視角輪廓變化約 0.245%～0.757%，仍可見局部光影及細節变化。柱向量測只涵蓋中段取樣，不能當完整柱直度證明。該床比例／橫桿尚有原始問題，保持未驗收；此流程不附帶或自動整合該實驗模型。
