# TRELLIS.2 50k 原始候選

色系與按鈕風格接近原圖，但整體結構錯誤。

**本件驗收：FAIL；尚未接入正式場景。**

參考圖使用既有 PNG；1024、seed 42、生成圖內目標 50,000 三角面，未做後期降面。
實際 49880 三角面、36325 頂點。來源 up，尺寸不是米制交付尺寸。

SHA-256：`24cc6f91797914116a1cad1f4494ce5ca3a7eb6fab276c9492ffda91d2fdaa16`。

[交付 GLB](../../../assets/models/bunker_command_console/trellis_50k_20261007/bunker_command_console.glb)
 · [原始 GLB](raw.glb)
 · [五視角檢查圖](qa_detail/contact-sheet.png)
 · [全批分析](../../../docs/research/2026-10-07-trellis-50k-requests.md)

- 生成四向重複控制台，頂視十字形；原圖要求單台三螢幕控制台。
- 側／背視角可見不合理的螢幕開口與相交板件。
- 剛體旋轉與縮放不能消除重複結構。
