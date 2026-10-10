# RV 引擎蓋鉸鏈動畫（2026-10-10）

[engine_hatch.gd](../../rv/engine_hatch.gd) 原本把整片維修蓋沿直線向上／前平移，開啟後脫離車身。本次保留閉合中心與原互動節點，以上緣後側 `(0, 0.28, -0.53)`（EngineBay 局部座標）為固定鉸鏈，向外旋轉 105°，一秒內緩入緩出。蓋板與碰撞使用同一姿態；動作前及逐幀沿旋轉弧線每 ≤1° 檢查，受阻或車輛移動時停在當下姿態，仍可反向關閉。

[engine_bay.tscn](../../rv/engine_bay.tscn) 補上固定框、鉸鏈、金屬框邊、凹入格柵和雙側伸縮支撐桿；把手移到下緣並完整納入碰撞。鉸鏈上方固定橫梁留出掀蓋淨空。引擎槽標示只在完全開啟時顯示。兩側桿長約 0.403–0.690 m，固定外筒 0.32 m，全程保留正長度內桿。

新增網格預算設定為每車 ≤1,000 三角面，實測新增 23 個 MeshInstance3D、836 三角面；整個引擎艙共 1,436 三角面。共用原生網格／既有材質，未新增貼圖或每幀生成網格。未量測多車同屏效能。

## 本輪自動檢查

Godot 4.7.2，統一 runner 分段執行：

```powershell
./scripts/test.ps1 -Godot 'C:/Users/evan4/AppData/Local/Programs/Godot/Godot.exe' -TestFilter 'test_rv_engine.gd,test_rv_experience.gd'
./scripts/test.ps1 -Godot 'C:/Users/evan4/AppData/Local/Programs/Godot/Godot.exe' -TestFilter 'test_rv_checkpoint.gd' -SkipImport -Smoke
```

- 資產匯入、引擎服務／所有權回歸、引擎蓋回歸、RV 磁碟檢查點及正式主世界啟動全部 PASS。最後調整把手碰撞及標示後另跑 `test_rv_experience.gd` PASS。
- [test_rv_experience.gd](../../tests/test_rv_experience.gd) 新增逐幀固定鉸鏈／碰撞同步、端點之外的弧線障礙、途中插入障礙、車輛移動中斷／反向，以及開／關穩定狀態讀檔姿態。
- 初次跳過匯入時，舊快取缺失造成 gas_can 繼承節點錯誤及檢查點逾時；重新完整匯入後同一檢查通過。未執行 full suite。

## 原生畫面觀察

在完整 starter_rv 的近景與側面觀察開啟、半開、全開及關閉，蓋板保持連在鉸鏈，支撐桿端點跟著移動，閉合回到框內；修正上方橫梁穿插後再次檢查全開。

依 AGENTS 執行 `rv_climb_playground.tscn -- --replay --climb-debug`：玩家與 Raker 均攀上車、隨腳本移動／轉彎保持支撐；按 F5 入座後顯示 `DESTROYED (1/3)`，怪物從屋頂落入車艙。引擎蓋及攀車原生日誌無腳本錯誤。測試視窗已關閉。

重播使用腳本車體運動；本輪未驗證真實輪驅操控、翻車或群怪。日誌保留於 gitignored `.godot/`，臨時工具／場景已清除，交付不包含截圖。
