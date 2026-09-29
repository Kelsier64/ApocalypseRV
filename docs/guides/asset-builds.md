# Raker 資產建置入口

目前正式模型為 `assets/models/raker/raker.glb`（v021）。建置、身體與手部稽核、匯出順序見 [v021 來源說明](../../art_source/monster_refined_v021/README.md)；遊戲整合與回歸入口見 [Raker 資產說明](../../assets/models/raker/README.md)。

v021 從 v020 Blend 建立新版場景；現有 `art_source/` 來源、各版依賴與驗證腳本繼續保留。依來源說明完成匯出與驗證後，才更新正式 GLB。

## 已移除的舊工具

2026-09-29 依使用者要求刪除已被 v021 流程取代的工具：

- `scripts/build_raker_animations.py`：v007→v008 的 22 段基礎動畫建置。
- `scripts/audit_raker_animations.py`：舊 `RAKER_GAME_EXPORT` 場景動畫掃描，目前改用 v021 的 `audit.py` 和 `audit_hands.py`。
- `scripts/raker_build_paths.py`：只服務上述舊建置腳本的路徑保護工具。
- `tests/test_raker_build_paths.py`：只測試已移除工具的 Python 測試。

[先前驗證紀錄](../validation/2026-09-29-prop-grayboxes.md) 中的建置保護與 Python 5/5 結果屬於刪除前的工作狀態。這次刪除以引用搜尋、文件連結及差異檢查驗證；沒有重新執行 Blender 建置或 Godot 全套測試。
