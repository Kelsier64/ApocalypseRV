# 油桶與汽油罐原模型保存

2026-09-29 依使用者要求改回灰盒，將原 GLB、四張伴隨 WebP 與六份 `.import` 原樣移入本目錄。搬移前後逐檔核對 SHA-256；原路徑、大小與雜湊見 [manifest.json](manifest.json)。作者、授權與可編輯原檔尚未核實，不由 GLB 的生成工具名稱推定。

本目錄以 `.gdignore` 排除 Godot 匯入，亦受 `art_source/.gdignore` 保護。`.import` 中的舊 `res://assets/` 與 `.godot/imported/` 路徑是**原設定快照**，不是當前執行期引用；不要讓它們在此重新匯入，也不要手動搬移 `.godot/imported` 快取。

目前遊戲仍使用 `props/gas_can.tscn`、`props/gas_can_empty.tscn`、`props/oil_barrel.tscn`，外觀改為灰色 BoxMesh／CylinderMesh；原碰撞、品質狀態、回收產出、質量、持物設定及保存路徑保留。空罐與滿罐沿用同形外觀，以原物品名稱區別。

## 日後取回

先確認目前工作樹沒有相同目的地檔案或新的模型引用。若要原樣恢復，按 manifest 的 original_path 還原整組 GLB、WebP 和 `.import`，再在保留的道具場景中將灰盒外觀替換成 GLB 實例。包裝根節點與碰撞不要覆蓋。恢復前後核對雜湊，重新匯入並驗證拾取／丟棄、加油回空罐、保存及場景啟動。

若製作減面或新版本，使用新的來源工作副本；保留本快照與來源紀錄。收存不代表批准刪除，也不代表模型已重新驗收。
