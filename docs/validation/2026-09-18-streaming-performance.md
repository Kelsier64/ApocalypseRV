# 串流 CPU 效能與回歸檢查

日期：2026-09-18。本次是 CPU 串流优化，未更改森林密度、畫質設定、世界生成版本或存檔格式。

## 實作

- 地形取樣、組裝與導航接縫以約 4ms 預算分幀，避免固定行數在複雜場址累積工作。
- v4 導航接縫共享頂點取樣由 3600 次減至 1204 次，三角形次序與座標相同。
- 樹幹碰撞先在場景樹外完成組裝再啟用，避免逐棵加入作用中的物理 body。此組裝區段不 await，不會在取消串流時遺留未掛入場景的 body。
- 森林渲染批次之間可以讓出執行；遠距怪物／物品清理從每幀改為每 0.5 秒，場址保護和區塊載入仍每幀執行。

## 量測

Windows，本機 Godot **4.6.1.stable.official.14d19694e**，headless/dummy；與專案要求的 4.7.2 不同，不能代替正式驗收。同一機器、seed 42、v4、依序生成 band 0 與 3，停用 actor 生成。CPU 時間為既有 `_measure_slice()` 累加，不包含 await 間的引擎工作；不是遊戲 FPS，也不是完整幀時間。

| 區塊 | 原始 CPU ms | 修改後 CPU ms | 原始最大批次 ms | 修改後最大批次 ms |
|---|---:|---:|---:|---:|
| 0 | 1115.29 | 652.40 | 74.40 | 34.09 |
| 3 | 1160.85 | 593.50 | 60.29 | 30.41 |

以上為各一次前後量測，修改後開啟慢批次診斷；不是統計效能保證。CPU 工作量下降約 42%／49%。牆鐘生成時間約 1811→1533ms、1851→1478ms。樹／灌木数量分別保持 1441／4097 與 1619／4562。地面 mesh／trimesh 碰撞建構仍有約 30–34ms 尖峰；4ms 是可切分工作的目標，不能中斷引擎單次呼叫。

可重跑 [benchmark_streaming.gd](../../scripts/benchmark_streaming.gd)：

```powershell
godot --headless --path . --log-file "$PWD/.godot/streaming-benchmark.log" -s res://scripts/benchmark_streaming.gd -- --profile-streaming
```

受限環境執行時，將該子程序的 APPDATA／LOCALAPPDATA 指向 `.godot/perf-user`／`.godot/perf-local`，避免讀寫玩家偏好與存檔。日誌保留於 `.godot/perf-*.log`，不提交。

## 本次檢查

- 通過：`test_streaming_generation`，相同種子的同步／分幀生成地形面、樹幹 transform、裝飾位置完全相同，完成後碰撞已掛入物理世界。
- 通過：`test_outdoor_horror`（100 seed、路線、導航與串流）、`test_outdoor_traversal`（搬運、室內進出與返回）、`test_forest_fog`、`main_scene_smoke`。
- 未通過：`test_world_generation` 的既有「Navigation crosses terrain band」。換回 HEAD 原始 chunk_generator 重跑也得到相同路徑終點 `(3.612844, 0.66949, -150.0)` 與失敗；未宣稱已修復。該測試使用 v2，未涉及本次森林碰撞修改。
- 正式 `scripts/test.ps1` 被版本核對阻擋：要求 4.7.2，本機只有 4.6.1，未修改或繞過 runner 核對。上述是額外的舊版診斷。
- 部分程序退出有 ObjectDB leak warning；本機也有 root certificate store 診斷，不能稱日誌完全無警告。
- `git diff --check` 通過。

## 實機限制

依 computer-use 技能嘗試啟動攀爬回放，Vulkan 成功辨識 RTX 5070 Ti，日誌有戰鬥更新，但兩次 `sky.list_windows()` 都未回傳遊戲視窗，故沒有取得可授權操作的 target window；未送出按鍵或宣稱觀察到攀爬／拆頂成功。已關閉本次啟動的測試程序。

尚未驗證：實際 FPS／GPU frame time、轉彎攀車與 F5 拆頂的視覺回放、長途輪驅、翻車與怪物群。需在專案要求的引擎版本和可擷取的遊戲視窗下補驗。
