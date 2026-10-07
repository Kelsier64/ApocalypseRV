# TRELLIS.2 50k 原始候選

轎車輪廓、四輪、車窗、燈組與鏽蝕磨損保留，未見明顯車體塌陷，整體外觀比控制台穩定。

**本件驗收：FAIL；尚未接入正式場景。**

參考圖使用既有 PNG；1024、seed 42、生成圖內目標 50,000 三角面，未做後期降面。
實際 49804 三角面、34839 頂點。來源 up，尺寸不是米制交付尺寸。

SHA-256：`518d8deea5511f47984bdbe75c21f7a30220214512e4bb213254d36f6ac6a44a`。

[交付 GLB](../../../assets/models/wreck_car/trellis_50k_20261007/wreck_car.glb)
 · [原始 GLB](raw.glb)
 · [五視角檢查圖](qa_detail/contact-sheet.png)
 · [全批分析](../../../docs/research/2026-10-07-trellis-50k-requests.md)

- GLB 一個 mesh／primitive／material，沒有 request 要求的獨立車漆接口；直接 material_override 會同時改輪胎、玻璃與金屬。
- 輪胎、窗框與車體部分邊緣融合／圓化；底盤翻覆視角未檢查。
- 2.44 × 2.00 × 4.73 m、底部原點、RoadsidePaint 與既有 Visuals 偏移／yaw 接入未完成。
