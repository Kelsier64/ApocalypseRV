# 灰井住宅城概念圖

2026-10-22。這兩張圖是本次以內建 `image_gen` 產生的原創設計參考，非遊戲實機截圖、既有模型或 2077 官方素材。保留原始輸出並複製到本目錄，未修改影像。圖中樓數、階梯、欄杆與細材質不是工程尺寸；實際製作以[副本計畫](../../plans/abandoned-megablock.md)的灰盒與低模規格為準。`.gdignore` 使本目錄圖像維持文件用途，不進入 Godot 資產匯入。

## 圖像

- [exterior-concept.png](exterior-concept.png)：外部量體、住宅格、核心筒、前庭入口與 RV 尺度。
- [atrium-concept.png](atrium-concept.png)：中庭、環廊、連橋、樓梯及冷天光／暖燈層次。

![外部量體](exterior-concept.png)

![中庭與連橋](atrium-concept.png)

## 原作參考連結

以下連到製作人作品頁；外部作品只作研究參考，本次沒有下載或收錄原作圖像，生成也未傳入外部參考圖片。

- [Krzysztof Olborski — Megabuilding / Cyberpunk 2077](https://krzysztofolborski.artstation.com/projects/WmWPDQ)：作者說明內外模組、組裝與優化工作。設計借鏡重複住宅格、巨型量體及中庭的空間組織。
- [Marcin Stępień — Cyberpunk 2077 Megabuilding Lighting](https://mstepien.artstation.com/projects/OoB4yg)：作者的巨型住宅燈光作品。設計借鏡中庭明暗層次，再依本作方向收斂成冷天光與少量暖色服務照明。

上述形體與氣氛的轉化是本提案的設計選擇，並非原作者對本專案的建議。灰井住宅城採獨立輪廓、布局、末日工業材質及原創名稱。

## 生成紀錄

- 模式：內建 `image_gen`，每張一個獨立 generate 呼叫，非 CLI／API fallback；未輸入參考圖片，背景不透明。
- 外觀原始輸出：`exec-91454009-ba85-482e-90b3-7cb0ea474020.png`。
- 中庭原始輸出：`exec-0384032a-bbff-4823-8941-608824c3ead3.png`。
- 已檢視圖像中的外觀／中庭／入口與動線意圖；場景實作仍需驗證實際尺度、碰撞、通路、光照及效能。

### 外觀完整提示詞

```text
Use case: stylized-concept.
Asset type: original game environment concept artwork for ApocalypseRV, a low-poly industrial survival horror game. This is an art-direction proposal, not an existing game screenshot.
Primary request: a colossal ABANDONED RESIDENTIAL MEGABLOCK called GRAYWELL BLOCK, inspired by the broad architectural idea of a vertical housing city with a hollow atrium, transformed into a grounded post-collapse concrete ruin.
Architecture: one coherent 96 meter wide, 72 meter deep, roughly 24-storey 116 meter tall residential megastructure, a chunky U-shaped rectangular volume around a deep open-air central courtyard. Many repeated small housing bays, huge external concrete ribs, two asymmetric service cores, recessed communal decks, pipes and sparse broken railings. It feels heavy and inhabitable, with engineered supports and believable facade grids. Most upper storeys dark and inaccessible. Original silhouette and layout.
Scene: the last apartment megablock of a former industrial settlement beside a forested mountain highway. Nearby low concrete ruins and encroaching sparse conifers, no futuristic surrounding city. A broad worn service forecourt in front. A small dark-green and cream survival RV parked at ground level gives unmistakeable enormous scale. Main entrance under a deep concrete canopy with two muted warm amber lights.
Style/medium: polished but practical environment concept rendered as a restrained low-poly 3D game world, large flat shaded geometric planes, simplified coarse low resolution material detail; readable architectural shapes rather than photorealism.
Composition: single wide landscape 16:9 low eye-level three-quarter exterior view from the approach forecourt, entire building silhouette visible, RV in foreground. Architectural subject dominates.
Lighting: cold overcast daylight, thin desaturated gray haze softens distant trees and the uppermost corners, foreground entrance and structure still readable; small warm amber entrance accent.
Materials/colors: weathered pale gray concrete, dark gunmetal service cages, soot stains, subtle rusty ochre, faded olive panels and sparse weeds. Decades abandoned. Mostly gray neutral colors with controlled brown details.
Text: no titles, no captions, no signs with legible words, no graphic overlay.
Avoid: dense neon, holograms, cyberpunk logos, glossy futurism, oversaturated blue/orange, dense vegetation covering architecture, impossible floating blocks, towering fantasy ruins, cinematic film grain, VHS, pixel grids, excessive high frequency detail. No UI, no watermark.
```

### 中庭完整提示詞

```text
Use case: stylized-concept.
Asset type: original interior environment concept for ApocalypseRV, an industrial survival-horror game. Concept only, not a real in-game capture.
Primary request: the enormous hollow residential courtyard INSIDE GRAYWELL BLOCK, a post-collapse abandoned concrete megablock. Build a coherent interior for a U-shaped 24-storey housing structure, with a courtyard approximately 32 meters across and repeated residential galleries far above the playable lower floors.
Camera: single wide 16:9 landscape first-person-eye-height view from a second-floor communal access gallery. Foreground railing clearly frames a vertiginous view over the huge empty courtyard. A broad supported pedestrian skybridge crosses at the third floor toward a warm maintenance doorway. The player should clearly understand the gallery, bridge, stairs and destination through the architecture. Two stair cores anchor opposite sides. Above them many repeated dark balconies climb toward a pale skylight of overcast sky.
Layout details: lower ground floor has closed neighborhood market shutters and a dead communal seating area; nearby hallway doors, utility ducts, hanging dry laundry scraps and a few abandoned chairs indicate ordinary residents lived here. Walkable gallery around 2.8 meters clear width, bridge around 3 meters wide with robust railings and solid supports; no narrow jumping route. Limited rubble kept away from the main passage. Some broken sections visible on a distant disused upper gallery, never an implausible floating bridge.
Style/medium: restrained practical low-poly 3D GAME ENVIRONMENT CONCEPT, deliberately simplified architectural geometry, flat broad concrete planes, coarse low-resolution material wear, simple silhouettes and sparse props. Match a dark-green/cream survival RV game's gray industrial world. Keep edges and spaces readable. Do not make it a glossy photorealistic architectural photograph.
Lighting/colors: cold neutral gray daylight filters down the central open shaft, soot-black door recesses, taupe and rusty ochre stains, very sparse faded olive panels. A few protected amber emergency fixtures mark the stair door and third-floor maintenance doorway. Dark but foreground floor and railings remain legible. Ceiling bounce and ambient light make traversal believable.
Atmosphere: eerie quiet, abandoned dense vertical neighborhood, unsettling empty scale and human traces, contained desaturated haze only in distant upper shaft.
Text: no captions, no title, no UI, no readable posters, no logos, no watermark.
Avoid: neon cyberpunk city, holographic advertisements, science-fiction machines, lush jungle, endless visually chaotic pipes, monsters, boss arena, elevator gameplay, obvious cinematic lens effects, pixelation, fog hiding the route, huge quantities of rubble.
```
