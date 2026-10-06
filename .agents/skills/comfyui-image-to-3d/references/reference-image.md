# 參考圖

有合適單圖就沿用。需生成／編輯時使用 imagegen；不要用 Python 改畫圖片。

將需求中已知形狀、部件與材質填入固定 prompt：

> Create ONE isolated [object] image for image-to-3D. Preserve [existing style reference / palette / materials / wear]. Keep [required components and structural relationships]. Show the complete object and every support foot, with visible structural joints. Weak-perspective three-quarter view, level composition, no camera roll, modest elevation, no wide-angle exaggeration. Members that the request defines as straight remain straight, parallel and joined at the requested angles; put wear in materials rather than bending the structure. Fabric and accessories do not hide important joints. Center the full object with clear margin. Transparent background, no floor or cast shadow, soft even lighting. No labels, text, grid, dimensions, collage, alternate views or extra objects.

編輯時用原圖作 target，列出要保留的外觀。生成後必須看圖，確認床腳、邊界、接點與原風格。水平、正交或鏡頭數值只是提示；不能當成已知 FOV 或校準投影。

不強制所有物件正面平視：會缺少深度資訊，本地床重畫較平視圖也未改善。PNG 須有非全不透明 alpha 與可見內容；腳本保留原 PNG bytes，使用 alpha 裁切，不再次去背。需要去背時用已授權 imagegen 編輯並另存。
