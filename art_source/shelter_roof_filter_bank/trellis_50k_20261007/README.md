# TRELLIS.2 50k 原始候選

三個前箱、同一前方底座與一條長風管都生成了，但風管脫離前方組件。

**本件驗收：FAIL；尚未接入正式場景。**

參考圖使用既有 PNG；1024、seed 42、生成圖內目標 50,000 三角面，未做後期降面。
實際 49962 三角面、33685 頂點。來源 up，尺寸不是米制交付尺寸。

SHA-256：`6bbf26bdbb60fb674af0fae1c4709440459d1ebe56835c78b5a767319da8eba3`。

[交付 GLB](../../../assets/models/shelter_roof_filter_bank/trellis_50k_20261007/shelter_roof_filter_bank.glb)
 · [原始 GLB](raw.glb)
 · [五視角檢查圖](qa_detail/contact-sheet.png)
 · [全批分析](../../../docs/research/2026-10-07-trellis-50k-requests.md)

- 頂／側視風管與前箱組分離；exact POSITION welding 後有 13 個連通片，所有片可分成前方 9 片與後管 4 片。两组 Z 包圍盒之間存在 0.026266 source-unit 空隙（總長約 2.6%），沒有任何片跨越，因此不是僅貼圖假象。
- 不符合一體共用底座、連續後方封閉風管的需求，剛體旋轉無法接回。
- 米制尺寸、中心原點和支座未驗收。
