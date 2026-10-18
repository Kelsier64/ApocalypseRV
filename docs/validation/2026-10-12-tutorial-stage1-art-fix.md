# 第一階段返修：光照與舊避難所美術

沿用 `codex/starting-tutorial`，仍等待第一階段驗收，未進入第二階段。

## 修正

- 原 236.8 m 屋頂使用未細分的大三角面，方向光 shadow pancaking 會漏光；結構表面細分至每邊不超過 8 m，保留物理碰撞形狀與全局日夜設定。
- 室內灯原本不投影，會照穿隔牆／閉合門；恢復燈具陰影。
- 門板原與隔牆重疊，滑開後藏進牆內只剩肋條；門軌前移 0.55 m。直接沿用舊避難所門板、把手、警示帶及材質。
- 所有按鈕使用舊外殼、面板、指示灯、獨立材質與按壓動畫；另一側按鈕轉向正確，射線可在牆／門之前選中開關。
- 內外牆重用舊避難所牆面模型的混凝土表層、接縫、破損、修補和滲痕；保留原 shader／貼圖。新增結構總計 157,878 三角面，低於 200,000 預算。[資產說明](../../world/tutorial_shelter/README.md)。

## 自動驗證

Godot 4.7.2。本輪未執行 full suite。

- `.godot/test-logs/20261012-204449-404-selected-31676/`：import、POI 契約、九區門／碰撞／導航、v11 保存恢復、主場景啟動全部通過。
- `.godot/test-logs/20261012-204729-109-selected-29664/`：最終牆面三角面預算、門板不埋入隔牆、兩側開關互動射線通過。渲染測試的 headless 模式只驗證灯具契約，明確略過像素檢查。
- 新 `test_tutorial_shelter_render.gd` 已分類 assets。原生 GPU 模式以零環境光、白色受光面，測試首／中／末區三種日照角度及跨隔牆／閉合門的點光源，共 11 組；每組都有移除遮蔽物的正對照，避免空白渲染誤過。
- Forward+ 與 Compatibility 實際像素檢查通過：遮蔽樣本的平均亮度增量為 0。Forward+ 的舊配置測試變體確實失敗：中區正午增量約 0.678、隔牆點光约 0.199、閉門點光约 0.064，證明測試可抓到原問題。日誌 `.godot/tutorial-shelter-render-{native,compatibility,legacy}.log`；圖片 `.godot/tutorial-shelter-render/<renderer>/{current,legacy}/`。

## 實機與驗收

Forward+、RTX 4060 Laptop GPU：以遊戲視窗查看舊牆面、關閉／開啟中的完整門板與綠／橙按鈕指示；最終資產另確認入口外牆與門框近景。輪驅回放於 80.8 秒通過八道內門、接回公路並封閉出口，日誌 `.godot/tutorial-stage1/lighting-fix-visual.log`；最終外牆觀察日誌 `.godot/tutorial-stage1/lighting-fix-final-facade.log`。受控回放不代表所有載重、自由駕駛或每種天候均完成驗收。

沿用[階段一入口](2026-10-11-tutorial-stage1.md)；新增 F8 門與按鈕近景，或啟動：

```powershell
godot --path . --log-file .godot/tutorial-art-review.log res://tests/tutorial_shelter_playground.tscn -- --inspect-gate --keep-open
```

正式遊戲重新啟動新場景後也會載入修正資產。請重看屋內漏光、開門後門板、兩側按鈕及牆面風格。完整表面美術／管線／效能調校仍留第六階段；教學終端與關卡條件仍未實作。

最終外牆檢查視窗關閉時出現清理警告：1 個 JoltShape3D RID、59 個 ObjectDB 實例及 1 個仍使用中的資源；尚未定位是否為既有退出清理問題。此限制與上述渲染／通行測試結果分開記錄。
