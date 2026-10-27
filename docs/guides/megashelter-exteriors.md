# 廢棄巨型住宅外殼：室外外殼製作指南

本指南描述目前實作的 Abandoned Megashelter 程序化室外外殼（資源 ID：`modular_megashelter`）。這是一個封閉的視覺場址，不含可玩室內、戰利品、敵人或進出轉場。尺寸及構件規格已接入 runtime；驗證狀態見文末紀錄。

## 幾何規格

- 網格：寬 4 m、高 4.5 m。
- 構件庫：wall、rib_wall、corner、pier、beam、vent、entrance、roof，以低多邊形幾何和材質變體控制成本。
- 模板：slab、twin wings、stepped。twin wings 為中央高量體與較低兩翼。
- 寬度：48、56 或 64 m；深度：32、40 或 48 m；高度：54、67.5 或 81 m。
- 不製作窗戶或窗框；使用牆板與封閉立面。入口整體約 12 × 9 m，車輛門片約 6 × 5 m，保持封閉。

slab 為單量體，twin wings 為中央高量體與較低兩翼，stepped 為階梯狀退縮。模板只改變建築輪廓，不代表內部功能。採用不透明封閉立面，不設窗戶或窗框；入口僅為封閉外觀細節。

## 外觀

使用冷灰混凝土、褪色灰綠與深鏽褐色。以牆板、樓層帶及量體退縮表現巨大住宅規模，避免鮮黃等高飽和警示色。保持簡潔輪廓，細節密度須適合遠距觀看。

## 場址、碰撞與導航

規劃資料包含 version、seed、template、volumes、modules、collision_boxes、building_bounds、site_bounds 及 access_point；各 bounds 由規劃計算。模組種類為 wall、rib_wall、corner、pier、beam、vent、entrance、roof。渲染端、正式 POI 放置與鄰帶導航需消費同一份規劃，勿各自重新抽樣或推算另一套建築尺寸。

碰撞覆蓋實際建築外殼，不應封死外圈步行接近空間。碰撞盒和導航排除區需依最終模組尺寸核對。封閉立面與門不需要互動碰撞或觸發器。此 POI 使用 OFF_ROAD 類別，不應註冊室內管理器、profile、物資或敵人。

## 生成規則

由生成 v18 的越野候選格以獨立 2% 機率選取；越野候選率保持 55%，其它 POI 權重不變。選擇使用獨立 RNG，不得消耗或改變道路 RNG 域。正式生成和鄰帶導航共用同一次場址規劃。`ModularMegashelter.configure_exterior(plan, include_visuals)` 依規劃組裝場景；導航端停用視覺節點，但沿用相同量體、碰撞與 bounds。

## 分幀建構與測試入口

六個實作階段均已完成。選定的自動檢查、正式場址 render／輪驅及效能量測已完成；完整自由遊玩尚未完成，正式世界全棟遠景受既有霧遮擋。詳細結果與測量限制見[本輪驗證](../validation/2026-10-27-modular-megashelter.md)。

視覺模型分材質合併建置，稀疏碎塊另行建置；行駛中的區塊串流使用約 4 ms 合作式分幀預算。單次 mesh／collision 建立仍不可中斷，因此此預算不是硬性幀時間上限。完整效能數據見驗證紀錄。

獨立樣板 `res://tests/megashelter_playground.tscn`：F2 外觀、F3 入口、F4 步行、F9 截圖、F10 樣板停車回放。`--capture --quit-after-review` 擷取樣板畫面，`--benchmark --quit-after-review` 輸出效能對照。正式世界樣板 `res://tests/megashelter_world_playground.tscn` 亦使用 F2、F3、F4、F9、F10；預設選用 seed 6 正式場址，可回放輪驅接近、停車及倒退離場。重現命令與限制見[本輪驗證](../validation/2026-10-27-modular-megashelter.md)及[外觀計畫](../plans/abandoned-megablock.md)。
