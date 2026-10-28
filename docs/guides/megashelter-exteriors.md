# 廢棄巨型住宅外殼：室外外殼製作指南

本指南描述目前實作的 Abandoned Megashelter 程序化室外外殼（資源 ID：`modular_megashelter`，內容版本 4）。這是一個封閉的視覺場址，不含可玩室內、戰利品、敵人或進出轉場。美術以[已選概念圖](../art/modular-megashelter/README.md)為準；本版生成多樣性與驗證狀態見[2026-10-28 多樣性紀錄](../validation/2026-10-28-megashelter-diversity.md)。

## 幾何規格

- 平面高度圖採 4 m 網格，視覺樓高 4.5 m；外牆按 13.5 m 大區塊組裝，設備帶高 1.4 m 並實際內凹。
- 核心構件為 wall、rib_wall、corner、pier、beam、vent、entrance、roof，另有 roof_plant、drain、service_spine 與 buttress。精確結構用原生幾何，屋頂重用既有空調機與過濾設備 GLB。
- 八種相連平面足跡：T、L、U、H、Cross、Z、Comb、Offset。翼部可有不同高度，形成不規則連接量體。
- 寬度：48、56 或 64 m；深度：32、40 或 48 m；高度：54、67.5 或 81 m。既有 massing 隨機域保留這些尺寸選擇。
- 不製作窗戶或窗框；使用牆板與封閉立面。入口整體約 12 × 9 m，雙片鋼門總寬約 7.2 m、高 6.24 m，保持封閉。

## 外觀與組合

結構選擇（五種）與立面色盤（三種）獨立抽選，沒有固定的樓型／結構／色盤家族綁定。各高度翼部依實際外露輪廓組裝立面，並按 13.5 m 高度帶分段；內院或相鄰翼部遮蔽的邊界不重複生成外牆。屋頂設備配置在各翼屋頂。入口位置由足跡前側邊界的連續可用區段推導。

使用冷灰混凝土、褪色灰綠與深鏽褐色。厚柱、服務凹槽、倒角、門框、軌道、加強肋、鉸鏈、百葉、女兒牆及剝落補片均以幾何呈現，磨耗由低解析著色補足。保持簡潔輪廓，不使用黃色外牆或警示漆。所有配置可由 seed 重現。

## 場址、碰撞與導航

規劃資料包含 version、seed、template、width、depth、height、structure、style、rhythm、volumes、modules、collision_boxes、building_bounds、site_bounds 及 access_point。`module_bounds()` 使用實際 kit 零件及屋頂資產的包圍代理計算 bounds；`solid` 附件的相同包圍盒加入碰撞計畫。渲染端、正式 POI 放置與鄰帶導航消費同一份規劃。

碰撞覆蓋實際建築外殼，不應封死外圈步行接近空間。碰撞盒和導航排除區需依最終模組尺寸核對。封閉立面與門不需要互動碰撞或觸發器。此 POI 使用 OFF_ROAD 類別，不應註冊室內管理器、profile、物資或敵人。

## 生成規則

由生成 v18 的越野候選格以獨立 2% 機率選取；越野候選率保持 55%，其它 POI 權重不變。選擇使用獨立 RNG，不得消耗或改變道路 RNG 域。正式生成和鄰帶導航共用同一次場址規劃。`ModularMegashelter.configure_exterior(plan, include_visuals)` 依規劃組裝場景；導航端停用視覺節點，但沿用相同量體、碰撞與 bounds。

外殼內容版本為 4。尺寸選擇沿用原 v1 massing RNG 域以維持既有 seeds 的寬／深／高抽樣；足跡、各翼高度、結構及立面則使用新版內容規劃。曾造訪內容版本 1、2 或 3 外殼的舊存檔依既有政策重新開局，不提供遷移。

## 分幀建構與測試入口

純觀察場景：[megashelter_viewer.tscn](../../tests/megashelter_viewer.tscn)。在 Godot 開啟後按 F6 執行目前場景，預設無霧、固定日光，不載入玩家或世界串流。滑鼠右鍵拖曳環繞、中鍵平移、滾輪縮放；1 全棟、2 入口、3 屋頂、F5 切換八種足跡、F6 換隨機 seed（隨機 seed 可選取全部八種）。根節點 Inspector 可設定初始 `seed_value` 與 `template_index`。也可執行 `godot --path . res://tests/megashelter_viewer.tscn`。

生成、seed 與視覺驗證狀態及未完成項目記於[2026-10-28 多樣性紀錄](../validation/2026-10-28-megashelter-diversity.md)。較早版本的場址、輪驅和美術結果保留於[歷史驗證索引](../README.md)，不代表本版驗證結果。

視覺模型分材質合併建置，稀疏碎塊另行建置；行駛中的區塊串流使用約 4 ms 合作式分幀預算。單次 mesh／collision 建立仍不可中斷，因此此預算不是硬性幀時間上限。
