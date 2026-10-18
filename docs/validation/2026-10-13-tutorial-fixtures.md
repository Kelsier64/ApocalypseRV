# 第一階段返修：吊燈固定、調暗及門牆交疊

沿用 `codex/starting-tutorial`；本次仍為第一階段返修，等待使用者驗收。

## 完成內容

- 重做共用工業燈殼、擴散罩、端蓋及護網。室內每盞燈以兩根吊桿、夾座和屋頂固定座連接；出口燈增加牆面支架。
- 室內光源能量由 2.4 降至 1.25，出口由 2.0 降至 1.0，燈罩自發光由 1.2 降至 0.45；保留陰影。
- 門軌距隔牆由 0.55 m 改為 0.85 m，增加軌道支架並同步移開內側按鈕。門框、過樑與牆體改為邊緣接合，門面警示帶移到補強條前方，避免埋入與交疊。
- 保留舊避難所材質與牆面資產。整體模型 162,522 三角面，仍低於 200,000 預算。

## 自動驗證

- `.godot/test-logs/20261013-005816-146-selected-24088/`：場址／碰撞／導航與模型檢查、checkpoint 回歸、主場景啟動全部通過。新增檢查涵蓋每盞燈的屋頂至燈殼連續支撐、端蓋接合、亮度，以及八內門和出口在關閉／半開／全開時，實際裝飾網格與牆面／門框的間距。
- 原生 Forward+ 和 Compatibility 各 11 組像素測試通過，全部遮蔽樣本亮度增量為 0；點光源無遮蔽物對照約 0.154／0.086。日誌：`.godot/tutorial-stage1/fixture-fix-render-final.log`、`fixture-fix-render-compatibility.log`。
- 原本門洞中央的無遮蔽物對照在調暗後為 0.057，低於既有 0.06 門檻；採樣點移到門洞內 x=-1.5 m，保留正式光源亮度與原測試門檻。沒有提高測試光源或放寬遮擋判定。

## 實機觀察與驗收入口

Forward+／RTX 4060 Laptop GPU：確認吊桿接至屋頂、燈殼與護罩、調暗照明及滑門開啟近景；已觀察角度未見門牆穿插。正式輪驅回放於 80.8 秒通過全部內門、接回公路並封閉出口。日誌 `.godot/tutorial-stage1/fixture-fix-final-visual.log`、最終近景 `.godot/tutorial-stage1/fixture-fix-review.log`。

```powershell
godot --path . --log-file .godot/tutorial-fixture-review.log res://tests/tutorial_shelter_playground.tscn -- --inspect-lamp --keep-open
```

F9 看吊燈、F8 看門框與門板、F6 看出口、F2 執行輪驅回放。檢視相機隱藏停在原地玩家的互動提示，F4 返回玩家時恢復。重新啟動正式新局也會載入更新。

## 限制

本輪未跑 full suite，也未逐一手動巡查所有距離／天候下的閃爍。原生程式退出時仍有前一輪已記錄的資源清理警告（59 ObjectDB、1 resource、1 JoltShape3D RID），尚未定位；像素與通行檢查結果另行列出。第二階段與第六階段剩餘美術未提前實作。
