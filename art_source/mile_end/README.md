# Mile End 鄉間小站

小站的琺瑯招牌、機械錶盤與油泵均為本專案原創。Godot 以公尺為單位組合店殼、棚架及家具，正面朝 +Z。油泵原點在底座中心，總高約 2 m，安裝在高 0.18 m 的泵島上。

若需重建，在專案根目錄用裝有 Pillow 的 Python 執行 `art_source/mile_end/make_artwork.py`，再用 Blender 5.2 執行 `blender --background --factory-startup --python art_source/mile_end/build_dispenser.py`。前者使用 Windows 的 Arial Bold 與 Consolas Bold 繪製圖稿，後者匯出內嵌機械錶盤的 GLB。[Godot 場景](../../world/roadside_pois/mile_end/station.tscn)負責碰撞、通道及物資點。

[試玩場景](../../tests/playgrounds/mile_end_playground.tscn)預設使用世界種子 25，從 RV 旁出發。可用 `-- --seed=3` 看落腳處配置，或用 `-- --capture` 擷取進場、前院、店內與油泵近景。
