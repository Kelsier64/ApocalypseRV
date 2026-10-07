# TRELLIS.2 50k 原始候選

較穩定的簡單候選：柱體、端面與縱向凸肋保留，五視角未見斷裂或與盆體融合，維持原圖灰色多邊形風格。

**本件驗收：UNKNOWN；尚未接入正式場景。**

參考圖使用既有 PNG；1024、seed 42、生成圖內目標 50,000 三角面，未做後期降面。
實際 50000 三角面、30197 頂點。來源 up，尺寸不是米制交付尺寸。

SHA-256：`2ef26e26cb09cb3b12bc8d2f135837c7f50ecaf56cecaffd86ef2bbdab3fab3a`。

[交付 GLB](../../../../assets/models/scrapper/trellis_50k_20261007/roller.glb)
 · [原始 GLB](raw.glb)
 · [五視角檢查圖](qa_detail/contact-sheet.png)
 · [全批分析](../../../../docs/research/2026-10-07-trellis-50k-requests.md)

- 端面與凸肋略不規則／圓滑；來源長軸 X，需求滾輪長軸本地 Y，需剛體轉向。
- 直徑 0.40 m、長 1.00 m、中心原點尚未校正；齒與盆體間隙未測。
- 交付一個 unique GLB 供兩支獨立節點各自實例化；CSGCylinder3D 型別、局部 Y 轉軸、雙滾輪運轉接口未實機驗證。
