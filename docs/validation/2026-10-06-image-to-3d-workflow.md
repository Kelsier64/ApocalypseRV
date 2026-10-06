# 單圖 3D 工作流工具驗證（2026-10-06）

本分支從同步後的 `origin/main`（`0c4d6cc`）建立，僅收錄工作流 skill、兩個自訂 subagent、固定 graph／工具與操作文件。既有床研究 GLB 僅作外部測試輸入；模型、圖片、node_modules、`.godot` 輸出及舊 API server 不在提交範圍。

## 本次執行

環境：Windows、Python 3.12.14／Pillow、Node 24.19.0、meshoptimizer 1.3.0、Godot 4.7.2。Python／Node 使用現有 Codex bundled runtime，skill 格式驗證使用現有 ComfyUI Python（PyYAML）；沒有重裝工具。

| 檢查 | 本次結果 |
|---|---|
| skill-creator quick_validate | 通過 |
| 自訂 subagent TOML、Python AST、Node syntax | 通過 |
| 8000 discovery／8188 nodes、weights、idle preflight | READY；未新增 GPU 工作 |
| 單次提交／收檔 client 行為 | 8 項通過：忙碌無提交、未知提交不重送、固定 graph／原圖、collect 不 POST、錯誤 history、缺 conditioning、精確 reconcile、損毀 GLB |
| 後期處理行為 | 8 項通過：預算未達 exit 2、受限／強制／no-op 的獨立保全、更新 SHA 後的 UV 竄改仍拒絕、縮放／鏡射姿態拒絕、不支援 node transform 拒絕且不建輸出 |
| 實際 Godot renderer | raw＋forced20k 同來源 up、同基準相機，各 5 textured＋5 clay；20 張 720×720 PNG，exit 0、無 script／render error，SHA／面數相符 |
| 實際圖像初查 | 已看 20 張 QA 總覽：完整物件、五視角、相同 framing；保留原始起伏／比例問題，未把床標為合格 |
| 獨立 agent forward review | 發現 raw PASS 與 final 面數預算互相阻塞；已明確將最終預算延後至降面後。未知提交／忙碌佇列／預算未達情境均停止新 submit，保留既有工作查證 |
| 相對連結、git diff --check | 通過 |

測試腳本與 QA 輸出位於本機忽略的 `.godot/workflow-checks/`，不附帶先前床實驗素材。Client submit 是 mock 行為測試；本次實際連線只做 preflight。固定 graph 的 GPU 生成依據屬[先前 profile 紀錄](../../.agents/skills/comfyui-image-to-3d/references/profile.md)，不是本次重新生成。

## 同一 raw 的降面結果

原始 49,916 三角面／37,823 vertices，SHA256：`9eff46de7573c67bddddd1a5968abfa4ef328ab04c2079f4c429f0f3313f5030`。所有測試後原檔不變。

| 模式 | 實際面數 | relative combined error | 結果 |
|---|---:|---:|---|
| 20k，cap 0.002 | 42,786 | 0.0019531009 | TARGET_NOT_REACHED、exit 2，保留證據並停止 |
| 20k，既有使用者授權的 force 實驗 | 20,000 | 0.0095652072 | 保全檢查通過；美術 UNKNOWN |
| 50k 預算，來源已符合 | 49,916 | 0 | no-op，GLB bytes／SHA 與來源相同 |

受限輸出 SHA：`d17499c1dd1861437678666d801f9f1d0831b0d88b8306d6ed3de3c9f041b28c`；強制輸出 SHA：`c7f871cdee0e6c864b65e20f13624e560b238a15a834816609067dfde1c05a42`，均重現先前樣本。逐頂點 mapping 驗證 POSITION／NORMAL／TEXCOORD_0／TANGENT bytes、材質與三張嵌入 PNG 相同；此 PASS 僅屬檔案／屬性保全，不能證明直度或遊戲接口合格。

## 範圍與限制

沒有新生成參考圖或 GLB、重新跑整批 request、替換正式視覺、修改 API server，也沒有執行遊戲行為套件。新自訂角色的 TOML 已驗證；目前 session 沒有 reload 新角色，需在此 checkout 的新 session 確認 role 後使用。此工作流會遇到第一個生成／幾何／風格／預算問題就停止回報，無法保證 image-to-3D 模型每次筆直。操作入口見[指南](../guides/image-to-3d-workflow.md)。
