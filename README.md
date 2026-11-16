# ApocalypseRV

Godot 4 第一人稱末日公路生存原型：駕駛 RV、搜刮建築、搬運物資、分解製作，並應對會追人、拆車的怪物。目前是單人沙盒，只有室外檢查點保存，沒有多人、任務或勝敗結算。

## 文件

| 想知道 | 看哪裡 |
|---|---|
| 設計意圖與玩家會遇到的規則 | [GDD.md](GDD.md) |
| 模組責任、狀態所有權與共用契約 | [architecture.md](architecture.md) |
| 各系統目前的功能、規則與實作 | [docs/systems/](docs/README.md#系統) |
| 製作流程、測試場、計畫與參考資料 | [docs 索引](docs/README.md) |
| 自動測試 | [tests/README.md](tests/README.md) |

## 啟動

安裝 [.godot-version](.godot-version) 指定的 Godot，將 `godot` 加入 PATH，在專案根目錄執行：

```powershell
godot --editor --path .
godot --path .
```

| 場景 | 用途 |
|---|---|
| `world/main_world.tscn` | 正式入口：兩室教學基地、完整循環、F6／F9 檢查點 |
| `world/cheat_test_world.tscn` | 現行世界生成加單間車庫，預設無限油、電與材料；沒有教學與檢查點 |
| `world/demo_world.tscn` | 固定種子 42 與小霧，材料與燃油無限；啟程後約 60 m 安排一次 Slender Speaker 遭遇；沒有檢查點 |
| `world/test_world.tscn` | 舊測試世界，配置不代表正式新局 |

```powershell
godot --path . res://world/cheat_test_world.tscn
```

預設使用 Forward+／Vulkan。顯示卡不支援時加上 `--rendering-method gl_compatibility --rendering-driver opengl3`，體積霧會降級為距離霧。各測試場的命令與快捷鍵見[測試場指南](docs/guides/playgrounds.md)。

## 怎麼玩

正式新局從兩室教學基地開始：在接待室啟動並帶走終端，到倉庫整備故障的 RV，把車開出大門後世界才開始運作。之後沿公路前進，停靠建築搜刮，把物品丟進分解機換成材料，在平板的 Crafting 頁製作燃油與零件。

起步：B 發動、C 一檔、Space 放開手煞車、W 油門。離座不會自動熄火或拉手煞車。

| 操作 | 按鍵 |
|---|---|
| 步行／衝刺／視角／跳躍 | WASD／左 Shift／滑鼠／Space；衝刺與跳躍消耗耐力，休息後恢復 |
| 蹲下／蹲走 | 按住 Ctrl；WASD 以 2 m/s 蹲走，放開後起身。頭頂受阻時保持蹲下，離開障礙後自動站起；蹲下時不能衝刺、跳躍或攀梯 |
| 梯子攀爬 | 空手或持小型物品面向梯子踏板，W 上爬、S 下爬、Space 脫離；從上方下梯時仍面向踏板並按 S；大型物品須先放下 |
| 撿物／加油 | 瞄準後短按 E；加油須手持汽油罐 |
| 副本進出 | 入口鋼門前短按 E；返回 B1 ENTRY 的 EXIT 門短按 E |
| 入座／開平板／拆裝輪胎 | 長按 E 約 1 秒；裝輪胎需手持 Wheel 瞄準輪槽，停穩並熄火 |
| 拆下固定物品 | 長按 F 約 2 秒解除固定並拾取，原設備占一格且使用雙手；車體結構不能 F 拆下 |
| 固定放置物品 | 拿著時短按 F，預覽時隱藏手持模型；左鍵確認、右鍵／Esc 取消並恢復手持顯示；R 貼面／直立，Q/E 轉 15°、Shift 轉 5°、方向鍵移 5 cm |
| 背包選取／丟棄 | 1–6 或滾輪／G；大型物品鎖定選取 |
| 屍體／大型物品分解 | E 拾取需雙手；G 丟入有電分解機，或手持對準固定分解機長按 E 1 秒投入 |
| 手電筒 | 在合成站製作；手持時按右鍵開關，滿電累計照明 5 分鐘，暫無充電 |
| 食用 | 選中食物後按住右鍵 2 秒；步行／蹲行可繼續，衝刺、跳躍、受傷或切換操作會取消 |
| 手槍 | 在合成站製作手槍與子彈；左鍵單發、按住右鍵瞄準、R 換彈；12 發彈匣，盒裝子彈每盒 24 發佔一格 |
| 駕駛 | W 油門、A/D 轉向、S 漸進腳煞車、Space 手煞車、E 離座。數字鍵 1–6 或滾輪切換手持小物件，需留一隻手握方向盤 |
| 引擎／車燈／排檔 | B 啟停、L 頭燈；Z 倒檔、X 空檔、C 一檔、R 升檔、T 降檔 |
| 車內照明 | 平板 Equipment 控制車內／維修燈及個別設備；Overview 控制頭燈；車內燈條可長按 F 拆裝 |
| 床鋪 | 停穩後在床旁按 E 躺下。休息每遊戲小時回復 10 SAN，可選擇略過 1、3 或 6 小時。按 E、Esc 或 Get up 起身 |
| 電池 | 手持電池對插槽短按 E 交換；長按 E 取出 |
| 引擎更換 | 車頭 E 開維修蓋；停穩、熄火、手煞車後，手持引擎短 E 交換，長 E 取出 |
| 引擎維修 | 手持引擎維修包，瞄準艙內引擎 H 3 秒，消耗一包補 150 耐久 |
| 其他維修 | 熄火停穩，瞄準設備／輪槽 H 2 秒花 2 金屬補 60 HP |
| 車體結構 | 平板 Structure 頁維修／重建／牆門互換；不能現場 H 維修 |
| 後坡板 | 後方控制盒 E；停穩、手煞車及合適地面即可展開；動畫期間板面無碰撞，可隨時按 E 反向 |
| 保存／載入 | 主世界 F6／F9；保存須在室外離座、結束互動且地形建立完成 |
| 設定 | Esc；開啟／關閉顯示、輸入及音量設定，偏好獨立保存。HUD 維持清晰 |
| 隱藏／顯示 HUD 與物品欄 | F12；同步切換準星、互動提示、血量／體力、時鐘、駕駛儀表及場景提示；設定與互動選單仍可使用 |
| 平板關閉 | TUI 或 shell 中按 Esc；shell 也可輸入 `exit` |

車載平板按 Ctrl+C 或 Ctrl+D 可退出管理介面進入 shell，布林值只接受小寫 `true`／`false`：

```text
cheat                         # 顯示目前三種開關；cheat status 亦可
cheat true                    # 全部開啟；cheat false 全部關閉
cheat fuel true               # 無限油
cheat power true              # 無限電，仍須裝妥可用電池
cheat materials true          # 無限制製作、建造及一般維修材料
cheat fly true                # 玩家穿牆飛行；Esc 關閉終端後開始移動
cheat fly false               # 關閉飛行，須位於足夠站立的空間
cheat fly status              # 查詢飛行狀態（也可輸入 cheat fly）
time                          # 顯示天數與時間
time set 18:30                # 設定當天時間
time set 08:00 3              # 設定第 3 天 08:00
weather                       # 顯示目前及目標天氣
weather set heavy_rain        # 立即設定天氣
```

天氣選項：`clear`、`overcast`、`rain`、`heavy_rain`、`fog`、`medium_fog`、`heavy_fog`、`storm`。作弊只作用於目前連接的 RV，讀檔或新遊戲後重設。完整規則見[能源、材料與製作](docs/systems/economy.md#車載平板與終端)。

## 驗證

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
```

預設匯入一次，執行所有根層 `tests/test_*.gd` 與正式主世界 smoke，遇到第一個失敗就停。篩選、其他參數與覆蓋範圍見[測試指南](tests/README.md)。Headless 通過不代替實機的手感、畫面、翻車、怪物群與長途經濟驗收。

## 程式位置

`player/` 玩家與互動、`enemies/` 怪物、`props/` 物品、`rv/` 底盤與車況、`equipment/` 設備、`world/` 串流／POI／建築、`core/` 共用契約、`tests/` 測試與測試場。目錄責任與清理規則見[程式與資產目錄指南](docs/guides/codebase.md)。
