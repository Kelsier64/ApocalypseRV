"""Original screen-printed enamel graphics for the Mile End station."""
from pathlib import Path
import random

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "world/roadside_pois/mile_end"
OUT.mkdir(parents=True, exist_ok=True)
INK, CREAM, RED = "#233937", "#dccca6", "#954a35"
FONT = Path("C:/Windows/Fonts")

def lettering(draw, center, text, size, color, face="arialbd.ttf"):
    draw.text(center, text, fill=color, font=ImageFont.truetype(str(FONT / face), size), anchor="mm")

def worn(image, name):
    rng = random.Random(name)
    draw = ImageDraw.Draw(image)
    for i in range(image.width * image.height // 85):
        x, y = rng.randrange(image.width), rng.randrange(image.height)
        w = rng.choice([1, 1, 2, 3, 6])
        draw.line((x, y, x+w, y+rng.randrange(2)), fill=rng.choice(["#8a775e", "#605746", "#ae9e81"]))
    folder = OUT if name == "enamel" else ROOT / ".godot/mile-end-art"
    folder.mkdir(parents=True, exist_ok=True)
    image.save(folder / (name + ".png"))

def station_sign():
    image = Image.new("RGB", (768, 384), INK)
    d = ImageDraw.Draw(image)
    d.rounded_rectangle((8, 8, 759, 375), radius=30, outline=CREAM, width=5)
    d.ellipse((60, 68, 275, 282), fill=RED, outline=CREAM, width=5)
    for i, length in enumerate([75, 61, 48]):
        y = 132+i*19
        d.polygon([(36+i*12,y), (128,y), (137,y+10), (128-length,y+10)], fill=CREAM)
    d.polygon([(148,207),(176,117),(183,162),(208,143),(174,232),(171,190)], fill=CREAM)
    lettering(d,(501,116),"MILE END",85,CREAM)
    lettering(d,(500,208),"MOTOR FUEL",47,CREAM)
    d.line((328,167,680,167), fill=RED, width=5)
    lettering(d,(386,321),"R O A D S I D E    S E R V I C E",27,CREAM)
    for x in [28,740]:
        for y in [28,356]:
            d.ellipse((x-4,y-4,x+4,y+4),fill="#7c7767")
    worn(image,"enamel")

def register():
    image = Image.new("RGB",(384,256),CREAM)
    d = ImageDraw.Draw(image)
    d.rectangle((8,8,375,247),outline=INK,width=6)
    lettering(d,(192,34),"MILE END   /   SERIES 4",19,INK)
    for y,digits,title in [(61,"0 1 3 8","TOTAL SALE"),(142,"0 0 7 2","GALLONS")]:
        d.rectangle((52,y,332,y+42),fill=INK)
        lettering(d,(192,y+20),digits,33,CREAM,"consolab.ttf")
        lettering(d,(192,y+58),title,14,INK)
    worn(image,"register")

if __name__ == "__main__":
    station_sign()
    register()
