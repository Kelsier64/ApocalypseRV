# 起始避難所外觀擴建驗收

日期：2026-10-01。此紀錄只涵蓋本次擴建；原開場功能的歷史驗收見 [2026-09-30 紀錄](2026-09-30-starting-shelter.md)。本輪未使用子代理或生成參考圖。

## 變更與美術狀態

- 建築占地 50 × 45 m，地面以上最高 14 m；兩側實心量體頂高 9／11 m，後方主樓 12 m，屋頂設備最高 14 m。新增區域只有裝飾與實體碰撞，不提供探索室內。
- 原車庫 20 × 28 × 6 m 淨空、7 × 5 m 門洞、32 × 30 m 前庭、出生與補給標記保留；沒有變更物資數量、存檔格式或開場狀態機。
- 新增複雜外殼及屋頂設備是**灰盒，正式模型未完成**。原簡單混凝土／鋼材表面、地板、車庫門和家具保留。當時的整體外殼 request（後續已撤回，見 [部件範圍修正](2026-10-01-shelter-native-art.md)） 指定替換範圍、朝向、尺寸及車庫淨空。
- [廢車 request](../modeling/requests/wreck-car/wreck-car.md) 補齊起始封路的共用 wrapper、28 輛堆疊／翻覆與精確接入轉換。其他已有 request 的設備不重複開單；簡單工作台與滑門沿用原生幾何。
- v7 共用場址邊界擴大，側後土坡改依建築範圍計算；舊 v2–v6 分支不變。新增碰撞盒標記 `navigation_solid`，烘焙時排除封閉體積，也支援鄰區來源重建。

## 自動檢查

- 起始開場與地形兩項修正後回歸通過，統一 runner 的匯入及正式主場景啟動／玩家移動通過。
- 新增物理射線和導航查詢：左右側翼與後樓具有實體碰撞，體積內沒有可走地面；原門口導航仍連通。
- 原測試涵蓋三台設備實際搬運安裝、按鈕冪等、整備暫停、門防夾／重試／永久封閉及重綁；擴大四個 seed 的場址整地／植被排除取樣，保留補給卸載重建、拾取身分與舊 v6 驗證。
- 首次檢查發現封閉盒體下方仍存在導航面，已使用投影障礙排除並經上述測試確認修正。API 依據：[Godot NavigationMeshSourceGeometryData3D](https://docs.godotengine.org/en/stable/classes/class_navigationmeshsourcegeometrydata3d.html#class-navigationmeshsourcegeometrydata3d-method-add-projected-obstruction)。
- 全套統一 runner：**90 項測試全部通過**，匯入、正式主場景啟動及玩家移動通過，程序退出碼 0。命令：`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Godot 'C:/Users/evan4/AppData/Local/Programs/Godot/Godot.exe'`。日誌位於 `.godot/test-logs/`，本輪清單另存 `manifest-shelter-expansion-full.txt`。
- 修改文件的相對連結與 `git diff --check` 通過。

## 實機觀察

Godot 4.7.2、Forward+／Vulkan、RTX 4060 Laptop GPU；使用正式世界衍生的 `tests/starting_shelter_playground.tscn`，日誌 `.godot/shelter-expansion-visual.log`。

- 外觀視角可見左右側翼、後方主樓與屋頂量體，前庭保持開放；畫面內未見植被穿入建築或前庭，建築與地面接合正常。08:00 陰天正面處於背光，量體可辨，複雜立面細節仍待正式模型。
- F2 啟動既有輪驅回放，實際開門、駕車出庫、轉向前進公路；HUD 與日誌顯示 `PASS: SHELTER_WHEEL_DEPARTURE`，22.9 秒，門狀態 `sealed`。行車使用油料與車輪控制，不在行駛時搬動車體 transform。
- 此次實機回放發生於導航排除修正前；後續修正僅影響導航資料，最終狀態由自動回歸驗證。已關閉自己啟動的測試視窗。

## 限制

沒有把自動化搬運／防夾／存檔測試算成逐項手動操作；沒有進行怪物群壓力測試。未交付外殼或廢車的最終 GLB，模型製作和接入後仍需重新視覺驗收。未遷移既有 v7 存檔中落在新增側翼／主樓體積內的任意外部位置；車庫開場各穩定階段的既有位置與物資流程由回歸覆蓋。
