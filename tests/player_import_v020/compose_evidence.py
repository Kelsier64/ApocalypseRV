"""Arrange actual Blender renders and Godot viewport captures without retouching."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont, ImageChops

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/validation/player-v020"
font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 23)
small = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 17)

def tile(canvas, path, box, caption, crop=None):
    image = Image.open(path).convert("RGB")
    if crop:
        image = image.crop(crop)
    x, y, width, height = box
    image.thumbnail((width, height - 36), Image.Resampling.LANCZOS)
    canvas.paste(image, (x + (width - image.width) // 2, y + (height - 36 - image.height) // 2))
    ImageDraw.Draw(canvas).text((x + 10, y + height - 29), caption, fill="#e7eced", font=small)

def pairs(name, poses):
    result = Image.new("RGB", (1800, 1220), "#19212a")
    draw = ImageDraw.Draw(result)
    draw.text((24, 15), "PLAYER v020 | Blender source / Godot 4.7.2", fill="white", font=font)
    draw.text((24, 49), "Same mesh, weights, UV and texture. Lighting / tonemapping differ; these are geometry and material inspections.", fill="#b4c4d0", font=small)
    for index, (pose, caption) in enumerate(poses):
        x, y = (index % 2) * 900, 90 + (index // 2) * 560
        tile(result, OUT / f"blender_{pose}.png", (x, y, 450, 550), f"{caption} | Blender")
        tile(result, OUT / f"godot_{pose}.png", (x + 450, y, 450, 550), f"{caption} | Godot", (175, 70, 945, 825))
    result.save(OUT / name)

pairs("pose_comparison_a.png", [("neutral", "Neutral"), ("side", "Side 60"), ("forward", "Forward 70"), ("elbow", "Elbow 90")])
pairs("pose_comparison_b.png", [("crouch", "IK crouch"), ("head", "Head turn"), ("fingers", "Fingers"), ("fp_pose", "FP arm pose")])
result = Image.new("RGB", (1680, 750), "#19212a")
ImageDraw.Draw(result).text((22, 15), "Blender GLB round trip | 11 meshes / 41 bones / no control bones", fill="white", font=font)
for i, pose in enumerate(["neutral", "forward", "crouch"]):
    tile(result, OUT / f"roundtrip_{pose}.png", (i * 560, 65, 560, 685), pose)
result.save(OUT / "roundtrip_comparison.png")
result = Image.new("RGB", (1600, 1360), "#19212a")
draw = ImageDraw.Draw(result)
draw.text((22, 15), "First-person acceptance | original full body and shadow retained", fill="white", font=font)
draw.text((22, 49), "Test cameras only. Original asset unchanged. Camera layers + disposable body view + shared shadow-only instances.", fill="#b4c4d0", font=small)
for i, (filename, caption) in enumerate([
    ("godot_first_person_down", "Local look down: body, gloves, legs and boots"),
    ("godot_first_person_hands", "Local hands: unobstructed"),
    ("godot_observer_shadow", "Observer layer: complete head and shadow"),
    ("godot_local_layer_shadow", "Local layer: head hidden, complete shadow"),
]):
    tile(result, OUT / (filename + ".png"), ((i % 2) * 800, 90 + (i // 2) * 630, 800, 630), caption, (0, 100, 1120, 840))
result.save(OUT / "first_person_comparison.png")
a = Image.open(OUT / "godot_observer_shadow.png").convert("RGB").crop((300, 480, 770, 730))
b = Image.open(OUT / "godot_local_layer_shadow.png").convert("RGB").crop((300, 480, 770, 730))
diff = ImageChops.difference(a, b)
evidence = {"shadow_comparison_region_pixels": [300, 480, 770, 730],
            "observer_and_local_shadow_pixels_identical": diff.getbbox() is None,
            "changed_pixel_bbox": diff.getbbox()}
(OUT / "visual_evidence.json").write_text(json.dumps(evidence, indent=2), encoding="utf-8")
print(json.dumps(evidence))
