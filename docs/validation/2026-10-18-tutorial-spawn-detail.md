# 教學出生點環境細節

2026-10-18，分支 `codex/tutorial-spawn-detail`，正式 v12 兩室基地。

## 內容

- 接待室新增接待桌／抽屜、紙本文件、椅子、原創區域地圖、時鐘、長椅、四格置物櫃、滅火器及終端框／配線／防滑墊。地圖是可編輯 SVG；小型物件採 Godot 原生幾何，沒有本輪 ComfyUI 生成資產。
- 維修室新增固定工具牆、扳手／鐵鎚、虎鉗、零件盤及桌下工具箱；兩室補上配電箱、門框護板、實體房號、排水格柵與四盞向下壁燈。
- 正式基地室內地板使用獨立材質，加入混凝土分縫、細裂紋、油漬及中央成對輪痕；外側前坪沿用原材質。新增塗裝材質重用原有舊金屬 shader。
- 靜態美術及碰撞分別為 [interior_details.tscn](../../world/orientation_shelter/interior_details.tscn)、[interior_details_collision.tscn](../../world/orientation_shelter/interior_details_collision.tscn)。沒有改動課程／存檔格式、物品 ID、原出生標記或門禁判定。

## 本輪檢查

Godot 4.7.2，PATH 安裝位置 `C:\Program Files\godot\godot.exe`。AGENTS.md 列出的舊安裝路徑本機無執行檔。

| 檢查 | 結果 |
|---|---|
| 新資產匯入 | PASS；`.godot/test-logs/20261018-195457-048-selected-21196/`。 |
| `test_orientation_shelter` | 最終 PASS；`.godot/test-logs/20261018-195803-561-selected-33372/`，場景分層、支撐、英文文字、門洞及車道。 |
| `test_orientation_warehouse` | 最終 PASS；`.godot/test-logs/20261018-195925-893-selected-26876/`，16 件原物資身份、連續膠囊接近路線、拾取視線、舊物資位置及八米車道。 |
| 新增幾何／邊界 | 419 個 MeshInstance、6,710 三角面；全部位於 building_bounds。新增預算為 10,000 三角面；原生簡單網格已低於預算，無需降面。全基地靜態總計 7,007 個 MeshInstance、548,160 三角面；不含執行時 RV、物品、角色、地形與文字。日誌 `.godot/spawn-detail/audit-final.log`。 |

首次倉庫檢查已印出全部行為 PASS，但結束時程序以 `-1073741819` 異常退出；沒有把該次記為通過。單獨重跑及維修桌最終位置檢查均正常以 0 結束。未修改引擎關閉或測試清理邏輯；既有關閉相容問題另見 [PR #46 紀錄](2026-10-18-pr46-ci.md)。

## 畫面與範圍

以正式主世界的 Forward+／08:00 整備光照，透過臨時相機擷取出生視角、接待室總覽、內門、RV 車道、維修區、桌面、置物櫃及工具牆。依畫面調暗初版地板、改用向下照明，並修正工具牆嵌入前牆的位置；最終近景可見工具板、桌面及虎鉗。最終程序正常結束，日誌 `.godot/spawn-detail/final-render.log` 無腳本錯誤。

這是實際世界的定點渲染檢查，沒有宣稱手動走遍基地或完成教學／駕駛，也沒有 FPS 基準測試。未跑完整套件或與本輪無關的攀爬／拆頂情境。

開啟 [orientation_playground.tscn](../../tests/orientation_playground.tscn) 按 F6，或正式主場景開新局，可檢視接待室的視覺密度、原終端可辨識度及維修室的布景。美術觀感仍由使用者驗收。
