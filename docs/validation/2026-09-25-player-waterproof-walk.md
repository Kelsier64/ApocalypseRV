# 2026-09-25 玩家防水工作服、微蹲步態與資產整理

## 本輪變更

在现有 1.60 m 角色上製作，保留手部重建、待機手肘方向、後腰修形、獨立純白面具與九組切口。無對講機。

衣料由粗織布方向改為 PU 塗層防水工作服：中性灰階 1024² Base Color、局部粗糙度約 0.52、方向性皺褶 Normal。反射使用 glTF 標準 PBR；沒有金屬度或額外清漆層，也沒有把燈光烘進貼圖。袖肘、腰側與膝後增加局部衣褶，部分折痕修改網格輪廓，保持所有切口環位置及權重。固定色圖集不變。

walk 重建為稍微下蹲、短步幅的警戒走路：骨盆下降 6.7–7.3 cm、上下起伏 6 mm、腳行程 21 cm、抬腳 3.8 cm，30 fps／37 影格／1.2 秒，首尾一致。root 始終固定，正確的向前屈肘方向保留。其餘 10 段 Action 不改動。

風格參考：[Helly Hansen PU 工作雨衣官方材質資料](https://www.hellyhansen.com/media/sheets/h/h/hhww_product_fact_sheet_70148_english.pdf)。步態依使用者要求的 CS:GO 微蹲感調整；[Valve 官方動畫更新](https://blog.counter-strike.net/2015/09/12492/)僅為背景資料，上述數值是本角色的原創設計，不是 CS:GO 骨架或動畫實測值。

## 本輪實際驗證

- Blender 5.2.2 LTS／MCP addon 1.7。由实际輸出 GLB 建立全新的 VERIFY_CURRENT 場景，與來源一起保存到 [Blender 原檔](../../art_source/player_masked_survivor/player_masked_survivor.blend)。
- 二進位 [正式 GLB](../../assets/models/player/player_masked_survivor.glb) 檢查：高度 1.60000002 m、腳底 0、55 骨、29 Mesh、5 材質、11 段動畫、9 份獨立斷肢；UV0、四骨權重上限、純白面具、root 不移動、循環首尾等皆通過。12,066 三角面，沿用先前肩部環線造成的 66 面超額。
- Blender 全 11 段 Action 逐幀檢查：所有頂點有限，權重正規化、最多 3 根有效骨；最大配對封口邊緣差約 0.000000119 m。walk 最大邊長比約 1.468。這不是自交與任意混合的完整證明。
- 本輪 walk 接地（鞋底 ±6 mm）：左 1–21、35–37；右 1–3、17–37。其他片段接地與長度更新於 [動畫清單](../../art_source/player_masked_survivor/animation_manifest.json)。
- Godot 4.7.2 統一 runner：import、test_player_model、main-scene 全部 PASS。逐幀驗證包含 idle/walk 手肘方向、walk 骨盆高度與 20–90° 膝屈曲、驅動腕與非持物手回歸。九份斷肢都能獨立載入。
- Godot Forward+／RTX 4060 Laptop 實際畫面：觀看微蹲步態，側面確認膝屈曲、手肘向後而前臂朝前；檢查衣料高光、整套赭色換色，以及室內低光。固定色頭套、手套、靴、反光條及面具保持原色。只關閉本輪獨立測試視窗，保留使用者編輯器。
- 首次整理後匯入有舊貼圖 UID 快取警告；資產重匯入完成後重跑整個 runner，三項全部通過。沒有忽略腳本錯誤或放寬 runner。
- 本輪未跑全部玩法測試，未把模型掛到正式玩家場景，也沒有測 RV、第一人稱或輪胎物理。

本機產生的完整證據位於 art_source/player_masked_survivor/work（glb_audit.json、blender_audit.json）、review（Godot 截圖）及 .godot/test-logs；這些輸出列入 gitignore，可依保留的驗證腳本再生。

## 整理結果

正式遊戲路徑統一為 assets/models/player/，測試和展示場同步更新。移走重複 revision7/8/9、舊根目錄 GLB／貼圖、重複來源 GLB、過時建模腳本與舊 1K／2K 衣料貼圖。移動記錄在本機 history/cleanup_before_waterproof/moves.json，另有六張過時衣料圖移入其 textures 子目錄。

遊戲玩家資產從 681 檔、約 219 MB，整理為 159 檔、約 35 MiB（包含 Godot 需要的各 GLB 抽出 PNG 與 .import）。七張當前 PNG 原檔、可編輯 .blend、現行製作／驗證腳本、切口表及遊戲資產保留。舊檔移入歷史目錄而未永久刪除。

根 .gitignore 排除玩家製作 history、revisions、work、previews、godot_review*、review、.blend 自動備份；既有 art_source/.gdignore 排除全部美術製作來源的 Godot 掃描。這是本次玩家建模產物的整理；既有 Raker 製作來源、使用者 todo、歷史 docs/archive 與無關程式修改均保留。

## 已知限制

本輪不代表最終近景美術驗收：衣領、褲襠、手掌仍簡化，衣褶為靜態高度場，沒有高模布料雕刻或即時皺褶。極端抬臂腋下仍有拉伸，部分攀爬角度可見細微封口差異。完整受傷爬行、死亡起始、道具精確握點及正式遊戲接入仍未完成。
