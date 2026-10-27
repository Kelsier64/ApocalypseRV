# 廢棄巨型避難所：模組外觀與世界接入

日期：2026-10-27。Godot 4.7.2；本輪完成外觀計畫六階段的實作及下列驗證，沒有製作可玩室內。使用者選擇沿用 `codex/f12-toggle-ui`。

## 完成內容

- 八類原生低模零件、三種樓型、4 m／4.5 m 網格；尺寸與輪廓由確定性種子產生。
- 封閉無窗立面、灰綠／冷灰／深鏽褐材質、閉合入口及稀疏碎塊；不配置黃色外牆、運作燈具、物資或敵人。
- 共用組裝資料供正式場景、簡化碰撞、bounds、地形與鄰帶導航使用；不在 `_ready()` 重新抽取場址外觀。
- 外觀合併成三個材質網格，碎塊另佔一個網格；新載入區塊按既有 4 ms 協作分幀預算建模。一次建模與分幀建模共用實作。
- 世界生成 v18；既有 55% 越野候選中以獨立 2% 抽選取代該格的一般候選。沿用地形拒絕條件，沒有保證每隔固定距離出現；道路及舊內容 RNG 保留既有域。
- Checkpoint 仍 v7、VehicleSnapshot 仍 v6，只接受目前世界生成 v18；依現有政策須重新開局。

## 自動檢查

| 檢查 | 本輪結果 |
|---|---|
| `test_streaming_generation.gd` | PASS，31.39 s；32 seeds、三種樓型、bounds、完整碰撞、重建、空 actor 首訪／回訪、普通及巨人跨帶繞行、封閉量體內無地面導航、實際分幀讓出及全部網格／材質與一次建模相同；原道路指紋維持 |
| `test_checkpoint_failures.gd` | PASS，17.70 s；當前世界及拒絕舊版本 |
| `test_poi_transition_persistence.gd` | PASS，3.24 s；既有副本進出與保存 |
| 正式主場景 smoke | PASS，8.55 s |
| 匯入、差異及文件連結 | 匯入成功；最終差異及新增／更改連結另核對 |

本機日誌位於 `.godot/test-logs/20261027-220646-221-selected-43312/` 及 `.godot/test-logs/20261027-215502-572-selected-42020/`。只跑相關測試，未跑完整套件。

## 實際渲染與輪驅觀察

- 檢查三種完整外觀、八類零件、入口近景及晴天／陰天材質；夜間以正式 Flashlight 資產照明檢查封閉入口，建築本身不亮燈。
- 使用 computer-use 選取唯一的測試遊戲視窗，觀察外觀、入口與套件，執行 F10 的持續輪驅回放；接近、停車及倒退離場成功。未用短按鍵冒充連續駕駛。
- 正式場址測試使用 world seed 6、row 33、column 2：自然排出的中央高塔，48 × 32 × 67.5 m，原點約 `(354.7031, 68.67067, -30388.99)`。實際地形與場景載入成功，近景入口及貼地位置已檢視，整地前庭上的正式 RV 輪驅停車／倒退離場 PASS。
- 另掃描到 world seed 4、row 89、column 0：56 × 40 × 54 m。兩個自然場址的碰撞場景驗證均成功，接近標記位於整地表面上 0.05 m。
- 實際世界仍有濃霧及載入視野限制，測試場的全棟遠景被霧遮蔽，不能以概念圖或獨立樣板聲稱正式世界遠距可見。沒有為此修改全域霧。

本機圖像及回放日誌均在 gitignored `.godot/`；代表檔名為 `megashelter-42-*-exterior.png`、`megashelter-42-2-night.png`、`megashelter-1194329244-1-world-entry.png`、`megashelter-interactive.log` 及 `megashelter-world-drive.log`。初輪材質對比與樣板初始化問題已修正，最終渲染／輪驅日誌沒有 script error。

## 效能

同一台 NVIDIA GeForce RTX 5070 Ti、Forward+、1280 × 800、相同相機及世界設定，預熱後各取 180 幀。比較同一場景隱藏／顯示大樓；此為受幀率限制的幀時間，不是未限幀 GPU 基準。

| 狀態 | 中位幀時間 | p95 | 畫面 draw calls |
|---|---:|---:|---:|
| 隱藏建築 | 5.917 ms | 7.002 ms | 1059 |
| 顯示建築 | 5.934 ms | 7.341 ms | 1067 |

seed 42／中央高塔的建築網格共 17,868 三角形；畫面增加的 draw calls 含陰影。一次建模初次約 42.39 ms，熱重建樣本約 15–19 ms；正式行駛串流採分幀路徑，沒有把一次建模時間宣稱為每幀固定成本。原世界整體初始化仍有數秒的同步地形建置，這次沒有解決既有串流尖峰。

## 重現

```powershell
godot --path . --log-file .godot/megashelter-review.log res://tests/megashelter_playground.tscn
godot --path . --log-file .godot/megashelter-world.log res://tests/megashelter_world_playground.tscn -- --replay --quit-after-review
```

獨立樣板：F2 外觀、F3 入口、F4 步行、F5 樓型、F6 seed、F7 天氣／時間、F8 套件、F9 截圖、F10 停車回放。`--capture --quit-after-review` 產生本機檢查圖；`--benchmark --quit-after-review` 輸出對照量測。正式場址樣板支援 F2／F3／F4／F9／F10，預設即上述合法 seed 6 場址。

尚未驗證：從公路長距離穿越崎嶇地形到達場址、所有種子的完整自由遊玩、低階硬體及大量建築同時可見。怪物繞行屬自動導航驗證；沒有聲稱已人工觀察自然追擊。室內探索不屬本輪範圍。
