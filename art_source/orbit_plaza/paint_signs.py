"""Paint the Orbit identity, enamel panels and illustrated depot advertisements."""
from pathlib import Path
import random
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parents[2] / "world/roadside_pois/orbit_plaza/signs.png"
W, H = 768, 256
INK, MILK, SUN, MINT = "#182e37", "#e6d5aa", "#e9a643", "#85b4ab"
atlas = Image.new("RGB", (W * 2, H * 5))
rng = random.Random(1959)


def lettering(draw, xy, text, size, color, font="bahnschrift.ttf"):
    draw.text(xy, text, font=ImageFont.truetype(font, size), fill=color, anchor="lt")


def emblem(draw, x, y, scale):
    def points(coords):
        return [(x + a * scale, y + b * scale) for a, b in coords]
    draw.ellipse(points([(18, 19), (110, 111)]), fill=SUN)
    draw.polygon(points([(0, 99), (74, 59), (136, 32), (95, 65), (34, 91)]), fill=INK)
    draw.line(points([(3, 103), (87, 76), (135, 39)]), fill=MILK, width=max(2, int(4 * scale)))


def panel(index, title, subtitle, footer, background, foreground):
    image = Image.new("RGB", (W, H), background)
    d = ImageDraw.Draw(image)
    d.rounded_rectangle((6, 6, W-7, H-7), 12, outline=foreground, width=3)
    if index == 0:
        emblem(d, 28, 36, 1.45)
        lettering(d, (250, 30), "ORBIT", 113, MILK, "arialbd.ttf")
        lettering(d, (255, 152), "T R A V E L   P L A Z A", 32, SUN)
    else:
        lettering(d, (30, 25), subtitle, 25, foreground)
        lettering(d, (28, 72), title, 76, foreground, "arialbd.ttf")
        d.line((30, 172, W-30, 172), fill=foreground, width=3)
        lettering(d, (31, 190), footer, 28, foreground)
    for px in (15, W-16):
        for py in (15, H-16):
            d.ellipse((px-3, py-3, px+3, py+3), fill="#685f50")
    for _ in range(580):
        x, y = rng.randrange(W), rng.randrange(H)
        if y < 20 or y > H-22 or rng.random() < .14:
            d.line((x, y, x+rng.randrange(2, 9), y+1), fill="#958872")
    atlas.paste(image, (index % 2 * W, index // 2 * H))


panel(0, "", "", "", INK, MILK)
panel(1, "MOON DINER", "O R B I T    /    L U N C H   C A R", "COFFEE     •     PIE     •     ALL DAY", MINT, INK)
panel(2, "DAILY SPECIAL", "M O O N   D I N E R     /     M E N U", "HOUSE BLEND    25¢       PIE SLICE    65¢", INK, MILK)
panel(3, "COLD DRINKS", "O R B I T     /     R O A D   M A R K E T", "ICE COLD      •      BOTTLED HERE", SUN, INK)
panel(4, "DISPATCH", "O R B I T     /     F R E I G H T", "DRIVERS   •   SIGN IN AT WINDOW", INK, MILK)
panel(5, "RECEIVING", "O R B I T     /     D E P O T   0 6", "PARCELS   /   MOTOR FREIGHT", MINT, INK)
panel(6, "MOTOR FUEL", "O R B I T     /     R O A D   S E R V I C E", "REGULAR     •     SUPER     •     DIESEL", SUN, INK)
panel(7, "LAST BUS", "C O A C H   L I N E S     /     N I G H T   R U N", "EASTBOUND    10:40 PM     /     BAY 02", MILK, INK)
poster = Image.new("RGB", (W, H), "#d6b485")
d = ImageDraw.Draw(poster)
d.ellipse((20,23,195,198), fill="#ca6948")
d.polygon([(0,176),(92,108),(153,151),(241,69),(360,158),(420,100),(480,185),(0,236)],fill="#536e69")
d.polygon([(0,212),(100,157),(183,193),(290,125),(418,191),(492,159),(560,256),(0,256)],fill=INK)
d.polygon([(20,256),(147,201),(219,198),(311,162),(239,204),(158,212),(91,256)],fill=SUN)
lettering(d,(405,22),"COACH LINES",47,INK,"arialbd.ttf")
lettering(d,(409,88),"The western run",35,INK,"georgiai.ttf")
d.line([(443,206),(518,171),(598,174),(692,148)], fill=INK, width=5)
for x,y in [(443,206),(518,171),(598,174),(692,148)]:
    d.ellipse((x-6,y-6,x+6,y+6),fill=SUN,outline=INK,width=2)
atlas.paste(poster,(0,H*4))

poster = Image.new("RGB",(W,H),"#cf9a56")
d = ImageDraw.Draw(poster)
d.polygon([(0,200),(322,28),(396,256),(0,256)],fill="#9e5846")
d.ellipse((39,172,284,221),fill=INK)
d.ellipse((50,164,275,206),fill=MILK)
d.ellipse((218,88,276,143),outline=MILK,width=12)
d.pieslice((77,15,232,184),0,180,fill=MILK)
d.rectangle((77,95,232,114),fill=MILK)
d.ellipse((77,82,232,110),fill=INK,outline=MILK,width=5)
for x in (118,147,171):
    d.arc((x,39,x+24,85),95,263,fill=MILK,width=4)
lettering(d,(337,28),"MOON DINER",58,INK,"arialbd.ttf")
lettering(d,(341,107),"Bottomless coffee",38,INK,"georgiai.ttf")
lettering(d,(344,195),"F R E S H   A T   D A W N",22,INK)
atlas.paste(poster,(W,H*4))
atlas.save(OUT)
