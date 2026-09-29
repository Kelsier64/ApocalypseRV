# 油桶／汽油罐灰盒、來源整理與建置保護

日期：2026-09-29。基準 commit `e877cc799d5079d9208252ac671d3c5efd6efe42`，包含本次工作樹修改。使用者要求將油桶／汽油罐換回灰盒、先收存原模型，並完成先前建議的資產來源整理與建置保護。原有 `AGENTS.md`、skill、盤點等未提交工作保留。

後續變更：使用者要求刪除過時腳本，因此舊 Raker v008 建置／掃描腳本、專用路徑工具及 Python 測試已移除，現行入口見 [建置指南](../guides/asset-builds.md)。下列建置保護與 Python 5/5 結果保留為刪除前的歷史驗證，並非目前仍有這些工具。

## 遊戲資產變更

`props/gas_can.tscn` 與 `props/gas_can_empty.tscn` 共用相同規格的中性灰 BoxMesh，尺寸 0.39759523×0.84584963×0.82353514 m，中心偏移沿用原碰撞 `(0.0022521876, -0.028735355, -0.0045410395)`。`props/oil_barrel.tscn` 改用半徑 0.32958984 m、高 1 m、16 段圓周的灰色 CylinderMesh。

保留根節點、場景路徑／既有 UID、碰撞、質量、回收產出、物品名稱、大小旗標與持物設定；外觀子節點名稱仍為 `gas_can`／`oil_barrel`。空罐和滿罐沿用同形外觀，原物品名稱仍區分內容。不新增存檔版本或更動物品行為。

原 GLB 兩份、WebP 四份與 `.import` 六份共 **12 個檔案**搬至 [來源保存區](../../art_source/retired_props/2026-09-29/README.md)，搬移前後 SHA-256 全部一致。該區與上層 `art_source/` 以 `.gdignore` 排除 Godot 匯入；原 `.import` 保留當時路徑作為恢復資料，不是目前引用。保存步驟与每檔雜湊見 [封存清單](../../art_source/retired_props/2026-09-29/manifest.json)。執行期程式／場景已找不到原 `assets/gas_can`、`assets/oil_barrel` 資源引用。

## 來源與建置流程

- 新增 [機器可讀 manifest](../archive/modeling-2026-09-29/asset-manifest.json) 與 [来源說明](../archive/modeling-2026-09-29/asset-provenance.md)，涵蓋原七個 GLB 家族。目前五個仍供遊戲使用，兩個收存；七份 GLB 的 SHA-256 均重新核對。來源、作者或授權不明時明確記為未知，沒有推測補值。
- 更新 `assets/models/` 入口，標明玩家 v020 正式外觀、v021 動畫提取與 Zombie 相容用途；修正 style_sample 的 bark 正式引用、加油站主世界接入現況及 Raker README 的 Zombie 生成描述。
- 2026-09-28 盤點保留原基線，增加後續狀態與保存位置連結；没有把歷史檢查冒稱為本次重跑。
- `scripts/build_raker_animations.py` 是舊 v007→v008 流程，預設輸出改為 `.godot/raker-animation-build/`；加入輸出／來源核對參數及覆寫保護，正式 Raker GLB 和目前開啟的來源 Blend 不允許覆蓋。原動畫製作段落不改，歷史 `art_source/` 腳本保持原樣。[建置指南](../guides/asset-builds.md) 記錄用法與限制。

## 本次目視觀察

以 `computer-use` 選取唯一的「ApocalypseRV - Asset Review 2026-09-29」遊戲視窗，沒有操作 Godot 編輯器。暫時展示程式載入實際場景、凍結 actor，以 Forward+／RTX 4060 Laptop GPU 顯示；F1–F4 切換頁面後刷新截圖。此為**獨立外觀初查**，不是正式世界光照、手持位置或互動驗收。檢查後關閉本次視窗，視窗清單確認不再存在。

| 畫面 | 可見觀察與判斷 |
|---|---|
| [灰盒](2026-09-29-prop-grayboxes/grayboxes.png) | 油桶是灰圓柱、兩種油罐是灰方盒；體積可辨，原高面數外觀已不顯示。 |
| [簡單道具](2026-09-29-prop-grayboxes/simple-props.png) | 廢鐵是白色方塊，輪胎是無可見輪圈細節的實心圓柱，辨識度改善優先；電池有綠色盒體與標示。後續先評估少量 mesh／材質改善及重用既有車輪，不直接排複雜建模。 |
| [引擎](2026-09-29-prop-grayboxes/engines.png) | 標準與升級引擎已有機塊、散熱／附屬件及配色；保留現有模型，尚無根據需要整件回退灰盒。 |
| [駕駛室](2026-09-29-prop-grayboxes/cockpit.png) | 座椅、方向盤、儀表、控制桿可辨識；保留既有複雜外觀。未檢查完整車廂的遮擋或駕駛中動畫。 |

展示程式存檔為 [review-scene.gd.txt](2026-09-29-prop-grayboxes/review-scene.gd.txt)，重現時複製到 `.godot/asset_review_20260929.gd` 再以 `godot --path . --log-file .godot/asset-review-20260929.log -s res://.godot/asset_review_20260929.gd` 啟動。切頁讀取按鍵事件，避免短按鍵被低幀率輪詢漏掉。[當次遊戲日誌](2026-09-29-prop-grayboxes/visual-review.log) 記錄四頁，沒有腳本錯誤。

## 自動驗證與限制

- 與基準場景比對：三個道具的根節點屬性、碰撞資源、碰撞節點與腳本引用區塊完全一致。
- 保存區 12 檔雜湊、manifest 七家族 GLB 雜湊及當前路徑核對通過；舊執行期資源路徑已無程式／場景引用。
- [Python 建置路徑測試](2026-09-29-prop-grayboxes/python-tests.txt) 5/5 通過，覆蓋預設暫存、顯式輸出、拒絕正式檔／來源檔、既有產物需明確覆寫及來源不符；`py_compile` 通過。未執行 Blender 完整動畫重建，不能宣稱新重建產物與現有 v021 等價。
- 角色測試自動重寫的 [本次蒙皮量測](2026-09-29-prop-grayboxes/skinned_bounds.json) 另存於本次目錄，原 `player-animations-v021/skinned_bounds.json` 歷史結果恢復原樣。
- Godot 4.7.2 統一 runner：**79/79 測試套件、資產匯入及主場景啟動全部通過，退出碼 0**。涵蓋道具資源循環、存檔、共享儲物、戶外拾取及場景串流；[完整結果清單](2026-09-29-prop-grayboxes/godot-results.json)、[執行時 manifest](2026-09-29-prop-grayboxes/manifest.txt) 與 [主場景日誌](2026-09-29-prop-grayboxes/main-scene.log) 已保存。manifest 是開始測試時的工作樹快照，當時的暫存 Python 快取已於測試後清理。
- 第一次受限執行停在 Godot 無法儲存使用者 editor settings，尚未跑測試；後以正常本機權限重新匯入並執行上述全套。此為環境寫入限制，不是測試通過紀錄。

本輪沒有修改其他道具外觀、沒有重新製作模型、沒有測量 LOD／FPS，也沒有新增正式建模 request。畫面初查、來源整理與灰盒替換各自完成，不將它們當成全部美術已定稿。
