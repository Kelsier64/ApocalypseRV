# Slender Speaker 腳部模型

日期：2026-10-10。依使用者要求改善腳部外觀，使用 Blender MCP 修改現有 A-rest 模型並更新正式 GLB。

## 改動

- 重建小腿下段至腳底的連續表面，補出腳踝骨點、跟腱、腳跟與內側足弓。
- 每腳五根獨立輪廓的腳趾，大拇趾朝內側；加入不同趾長、趾節、足背肌腱及十片趾甲。
- 沿用暗褐乾燥皮膚及髒污角質材質，僅烘焙腳部的新 UV 區域。
- 保留現有腳踝骨位置、55 根骨架及全部 15 段動作，不增加腳趾骨或改寫追蹤／攻擊行為。

模型為 **38,966 三角面、6 材質、6 張 2K 貼圖**，仍在原本 40,000 三角面預算內。專用 `.blend`、重建與烘焙脚本保留於本機 `art_source/slender_speaker/`；舊靜態模型與油桶製作檔未修改。

## 檢查結果

| 檢查 | 本輪結果 |
|---|---|
| Godot 重新匯入及 `test_slender_speaker_animation` | PASS，批次 `20261010-014610-654-selected-8120` |
| 15 段動畫取樣及 inverse bind matrices | 與修改前逐位元組相同 |
| 身體三張貼圖的新腳部區域以外 | 變更像素皆為 0，保留手與其他身體貼圖 |
| 身體網格 | 0 邊界邊、0 非流形邊、0 零面積面 |
| Blender 逐幀腳底高度，walk 145 次／run 61 次 | 最低約 −0.000002 m，屬浮點誤差；沒有新增腳底穿地 |
| Godot 原生畫面 | 檢視近照、側面及走動視窗，另檢查跑步影格 |

[資產核對資料](images/slender-speaker-feet/asset-audit.json) · [測試結果](images/slender-speaker-feet/results.json) · [動畫測試日誌](images/slender-speaker-feet/animation-test.log)

首次在受限環境匯入時，Godot 因無法存取自己的編輯器設定目錄而將匯入命令判為失敗；使用正常權限重跑後，匯入與測試均通過。原生預覽仍有既存 shader cache 警告，沒有遊戲腳本錯誤。

## 畫面

[腳部近照](images/slender-speaker-feet/feet-close.png) · [側面](images/slender-speaker-feet/feet-side.png) · [背面](images/slender-speaker-feet/feet-back.png) · [全身比例](images/slender-speaker-feet/full-model.png)

[走路預覽](images/slender-speaker-feet/walk.webp) · [跑步預覽](images/slender-speaker-feet/run.webp)

使用正式 Godot visual wrapper 與更新後 GLB，在獨立燈光場景以 30 fps 取樣既有原地動畫，共 204 幀。這是模型、材質及動作變形檢查，未重測 AI、車輛攻擊或所有地形坡度。完整身高仍為 15 m，原點及朝向沿用正式場景契約。

[原生日誌](images/slender-speaker-feet/native.log) · [GLB 雜湊與影格資料](images/slender-speaker-feet/manifest.json) · [錄製程式](images/slender-speaker-feet/capture-source.gd.txt)

本段完成後停止，交由使用者檢查外觀。

## 後續功能：踢到／踩到玩家扣 40 HP

同日後續加入 `slender_speaker_foot_contact.gd`，此節記錄新的傷害驗證；以上模型／材質結果保留原本範圍。腳跟、腳掌及五個腳趾的接觸取樣跟隨正式左右腳骨架，沿每個物理步的姿勢與世界移動掃掠。新接觸透過 `Player.take_damage(foot_player_damage)` 扣 40 HP，持續重疊不重扣，分開後再次接觸可再受傷；左右腳共用玩家既有 0.5 秒受傷無敵與死亡流程。車板、設備及一般實體保留遮擋，後續動畫越過障礙也不能從另一側誤傷；腳部不扣設備耐久。沒有修改模型或動畫資產。

- 六項相關測試全部通過：抓取、處刑、腳部傷害、移動砸擊、自主 playground 設備及砸擊玩家；日誌 `.godot/test-logs/20261010-125754-624-selected-43936/`。
- 腳部測試將正常步態移動明確放在真正物理步後重新通過：`.godot/test-logs/20261010-130114-205-selected-30540/`。4 m/s 走路於第 52 步接觸、10 m/s 跑步於第 20 步接觸，各自扣 40 HP；使用正常 `move_and_slide` 的角色碰撞及原有骨架動畫，沒有移動腳骨來代替這兩案。
- 同一測試另驗證前進掃掠、下降踩中、接觸後保持重疊、分開再接觸、雙腳同時碰到、身體碰撞但腳部未接觸、牆／車板／Item 當次與後續遮擋、正式物理回呼、傳送／還原及致命傷後死亡／復活。
- 原生 Forward+／Vulkan：`.godot/slender-foot-native-physics.log` PASS，畫面檢查可見正式腳掌碰到玩家，HP 100→60、命中數 1。約 0.88 秒接觸時巨人根位置 Z=2.47 m，身體尚未撞到玩家。暫停姿勢只發生在傷害已驗證後，測試視窗已關閉。

原生輔助程式使用已還原的正式玩家、腳部動畫及真正物理步內的移動，不使用 render delta 代替物理時間。它驗證腳部接觸位置，沒有重測完整自主追逐、坡地、翻車或怪物群；此次也未執行 full suite。
