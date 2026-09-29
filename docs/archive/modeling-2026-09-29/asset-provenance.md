# 匯入資產來源與用途

> 歷史快照：2026-09-29 封存，保留當時觀察與規則，不再日常更新。現行流程見 [建模入口](../../modeling/README.md)。

[asset-manifest.json](asset-manifest.json) 以七個原執行期 GLB 家族為單位，記錄目前消費場景、來源檔／腳本、歷史版本、狀態及 SHA-256。路徑以專案根目錄為基準；外部絕對路徑只是既有 README 留下的來源線索，未重新核對存在或可重建性。[inventory-models.md](inventory-models.md) 保留 2026-09-28 搬移前的靜態盤點與原始面數，應按其盤點日期閱讀。

油罐與油桶的高面數 GLB、WebP 和 `.import` 一起保存於 `art_source/retired_props/2026-09-29/`，由 `.gdignore` 隔離 Godot 匯入；搬移前後逐檔雜湊見[封存清單](../../../art_source/retired_props/2026-09-29/manifest.json)。`props/gas_can.tscn`、`props/gas_can_empty.tscn`、`props/oil_barrel.tscn` 保留原路徑和行為，以原生灰盒提供目前外觀。來源 manifest 中這兩家族的 `original_runtime_glb` 指搬移前路徑，`current_glb` 指封存位置。

待查資料：油罐／油桶的作者、取得來源、可編輯原檔及授權；Zombie 外部 GLB 的可用性、可編輯原檔與授權；玩家 v020 外部 Blender／交付檔的現存狀態與授權；Raker 早期外部動畫場景的現存狀態與授權。GLB 的生成工具欄位、已保存的絕對路徑和專案自製描述都不能單獨證明這些資訊。
