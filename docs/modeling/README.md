# Image-to-3D 建模 request

Requests 僅用於家具、道具、設備或獨立建築部件；整棟建築、整體外殼、牆體、地板、屋頂與場景配置由場景製作直接完成，不交給 image-to-3D，也不以整棟建築 request 取代實作。

日常流程見專案 [3D skill](../../.agents/skills/apocalypse-rv-3d-scenes/SKILL.md)：簡單物件直接完成；複雜裝潢、道具或設備先建立 `requests/<名稱>/` 資料夾，使用 [短模板](TEMPLATE.md) 寫入 `requests/<名稱>/<名稱>.md`，供使用者後續製作參考圖並透過 image-to-3D diffuser 生成模型。場景需要先能使用時，建立必要灰盒、碰撞與互動；收到模型後再替換外觀並驗證。寫 request 時不必同時生成圖片；已有參考圖時放在同一資料夾並在 request 中連結。

大建築可依需要拆成可獨立製作與替換的部件，例如複雜外牆、入口組件、屋頂設備或室內裝潢，各自建立 request 並記錄所屬建築、局部擺位與接合需求；整體配置與組裝留在 Godot 場景。同一部件的重複實例共用一份 request，簡單牆面與地板仍直接完成。

待建模型需求放在 [requests/](requests/)，每個模型只維護一份 request，完成情況直接寫在裡面，不另列進度清單。油桶／汽油罐已依使用者要求補上建模需求，交付前維持灰盒，[收存原件](../../art_source/retired_props/2026-09-29/README.md) 繼續保留。

舊盤點與來源資料僅供歷史查閱：[2026-09-29 資產盤點](../archive/modeling-2026-09-29/inventory.md)、[來源快照](../archive/modeling-2026-09-29/asset-provenance.md)。不要求日常更新。
