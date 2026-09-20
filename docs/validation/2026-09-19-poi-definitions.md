# POI 共用定義與製作規範

日期：2026-09-19。基準 `eac3294811461f8552485ef86273cb6f739714f9` 加先前加油站／GLB 未提交工作及本輪變更。

## 變更

- [共用規範](../guides/poi-authoring.md) 統一兩類 POI 的座標、分層、素材、場址、物資及保存責任，保留副本入口與直接探索的差異。
- [PoiDefinition](../../world/poi_definition.gd) 及 `world/poi_definitions/` 六份資源：舊 v2 維修站、四款 v3／v4 入口、加油站。
- [POIConfig](../../world/poi_config.gd) 集中場景及顯示名稱。POISpawner 和鄰帶導航共用解析器；四款隨機池順序保留，加油站不自動加入。
- 副本入口依定義路徑接線，直接探索型保留同世界場景，不接 PoiInstanceManager。
- 加油站 AccessPoints 前門／維修間標記朝向調為 local -Z 朝外，不改門洞、碰撞或玩家路線。
- 更新房型規格入口、architecture、GDD 及 POI 計畫；房型資料表與多樓層仍未勾選完成。

## 自動驗證

Godot 4.7.2 stable／Windows／headless。

專項 runner 匯入、test_poi_definitions 及主場景啟動通過。最後追加的路徑／分層負例也通過，日誌 `.godot/poi-definitions-final.log`，退出碼 0。

檢查包括：六份定義可載入及生成、同場址 ID／seed 保留、副本入口只接一次、直接探索型不註冊轉場且不自行產生道具、未知 ID 無靜默回退、缺入口標記與不合法範圍拒絕、巢狀 Visuals 內碰撞拒絕、自訂入口路徑可接線。

改動前擷取生成 v2／v3／v4、seed 0／1／42／99、各 12 場址，共 144 場址的完整規劃、物資計畫及建築位置地形高度。重整後位元組指紋保持相同：`9a0b9c7b180bdf16c6e6a7062403154ae5ab0b056d96ad57b332abc529b4900b`。這驗證了本批樣本的資料不變，不宣稱所有動態物理逐影格重播。

完整 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1` 通過匯入、38 個測試套件及主場景 WORLD_READY_FOR_PLAY，退出碼 0，日誌位於 `.godot/test-logs/`。最後補強錯誤提示與非法本地路徑提早拒絕後，另跑 `test_poi_definitions.gd`／`test_poi_resources.gd`，皆通過且退出碼 0；最終日誌為 `.godot/poi-definitions-final.log`、`.godot/poi-resources-final.log`。文件相對連結及 `git diff --check` 也通過。

## 限制與後續

本輪未重建舊入口的 Silhouette／碰撞；四份定義以 legacy_visual_layout 明確追蹤例外。場址 AABB 是安置需求與靜態檢查資料，既有整地、步道及串流保護規則維持原樣。content_version 未加入 checkpoint 序列化，新增室內 profile、改布局及新生成池仍須另做版本／保存策略。

本輪沒有重跑人工畫面檢查；未改渲染、碰撞或 RV 物理。加油站與模型的先前畫面證據分別見 [灰盒驗收](2026-09-19-gas-station.md)、[GLB 驗收](2026-09-19-fuel-pump-import.md)，不當作本輪新增驗收。
