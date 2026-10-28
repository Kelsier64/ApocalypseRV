# 廢棄巨型住宅外殼：室外外殼製作指南

本指南描述目前實作的 Abandoned Megashelter 程序化室外外殼（資源 ID：`modular_megashelter`，內容版本 3）。這是一個封閉的視覺場址，不含可玩室內、戰利品、敵人或進出轉場。美術以[已選概念圖](../art/modular-megashelter/README.md)為準；本輪重作與限制見[2026-10-28 紀錄](../validation/2026-10-28-megashelter-variation.md)。

## 幾何規格

- 水平接合為 4 m，視覺樓高為 4.5 m；外牆按 18 m 大區塊組裝，設備帶高 1.7 m 並實際內凹。
- 核心構件仍為 wall、rib_wall、corner、pier、beam、vent、entrance、roof，另有 roof_plant、drain 與 service_spine 附件。精確結構用原生幾何，屋頂重用既有空調機與過濾設備 GLB。
- 模板：slab、twin wings、stepped。twin wings 為中央高量體與較低兩翼。
- 寬度：48、56 或 64 m；深度：32、40 或 48 m；高度：54、67.5 或 81 m。
- 不製作窗戶或窗框；使用牆板與封閉立面。入口整體約 12 × 9 m，雙片鋼門總寬約 7.2 m、高 6.24 m，保持封閉。

slab 為單量體，twin wings 為中央高量體與較低兩翼，stepped 為階梯狀退縮。模板只改變建築輪廓，不代表內部功能。採用不透明封閉立面，不設窗戶或窗框；入口僅為封閉外觀細節。

## 外觀

內容 v3 使用三種暗色建築風格：灰綠混凝土、冷灰藍鋼板、灰橄欖設備外殼。獨立 architecture RNG 控制柱寬／間距、退台偏移及 1–3 台屋頂設備；退台上層完整落在下層內。立面有八種修補／剝落變體、可變百葉密度與設備豎井，入口增加分層裝甲、鉸鏈座及閉鎖桿。所有變化可由 seed 重現。

使用冷灰混凝土、褪色灰綠與深鏽褐色。3.2／4.0／4.4 m 寬的主柱高出相鄰量體，配合深凹服務帶分出大塊封閉立面。倒角、厚門框、軌道、加強肋、鉸鏈、百葉、女兒牆及剝落補片均有幾何，磨耗由低解析著色補足。保持簡潔輪廓，不使用黃色外牆或警示漆。

## 場址、碰撞與導航

規劃資料包含 version、seed、template、volumes、modules、collision_boxes、building_bounds、site_bounds 及 access_point。`module_bounds()` 使用實際 kit 零件及屋頂資產的包圍代理計算 bounds；`solid` 附件的相同包圍盒加入碰撞計畫。渲染端、正式 POI 放置與鄰帶導航消費同一份規劃。

碰撞覆蓋實際建築外殼，不應封死外圈步行接近空間。碰撞盒和導航排除區需依最終模組尺寸核對。封閉立面與門不需要互動碰撞或觸發器。此 POI 使用 OFF_ROAD 類別，不應註冊室內管理器、profile、物資或敵人。

## 生成規則

由生成 v18 的越野候選格以獨立 2% 機率選取；越野候選率保持 55%，其它 POI 權重不變。選擇使用獨立 RNG，不得消耗或改變道路 RNG 域。正式生成和鄰帶導航共用同一次場址規劃。`ModularMegashelter.configure_exterior(plan, include_visuals)` 依規劃組裝場景；導航端停用視覺節點，但沿用相同量體、碰撞與 bounds。

外殼內容版本改為 3，輪廓類型與寬／深／高的抽樣仍使用原 v1 massing 域；結構分段、柱碰撞及外觀已更新。已造訪內容版本 1 或 2 外殼的舊存檔依既有政策重新開局，不提供遷移。

## 分幀建構與測試入口

純觀察場景：[megashelter_viewer.tscn](../../tests/megashelter_viewer.tscn)。在 Godot 開啟後按 F6 執行目前場景，預設無霧、固定日光，不載入玩家或世界串流。滑鼠右鍵拖曳環繞、中鍵平移、滾輪縮放；1 全棟、2 入口、3 屋頂、F5 切換樓型、F6 換隨機 seed。根節點 Inspector 可設定初始 `seed_value` 與 `template_index`。也可執行 `godot --path . res://tests/megashelter_viewer.tscn`。

六個實作階段均已完成。v3 通過 32 seeds 與固定尺寸多樣性檢查，並完成三種樓型／風格的無霧樣板渲染；完整自由遊玩與最終美術確認尚未完成。v1 的正式場址與輪驅結果保留於[初版紀錄](../validation/2026-10-27-modular-megashelter.md)，本輪沒有重跑輪驅情境。詳細結果與測量限制見[本輪驗證](../validation/2026-10-28-megashelter-variation.md)。

視覺模型分材質合併建置，稀疏碎塊另行建置；行駛中的區塊串流使用約 4 ms 合作式分幀預算。單次 mesh／collision 建立仍不可中斷，因此此預算不是硬性幀時間上限。完整效能數據見驗證紀錄。

獨立樣板 `res://tests/megashelter_playground.tscn`：F2 外觀、F3 入口、F4 步行、F9 截圖、F10 樣板停車回放。`--capture --quit-after-review` 擷取樣板畫面，`--benchmark --quit-after-review` 輸出效能對照。正式世界樣板 `res://tests/megashelter_world_playground.tscn` 亦使用 F2、F3、F4、F9、F10；預設選用 seed 6 正式場址，可回放輪驅接近、停車及倒退離場。重現命令與限制見[本輪驗證](../validation/2026-10-27-modular-megashelter.md)及[外觀計畫](../plans/abandoned-megablock.md)。
