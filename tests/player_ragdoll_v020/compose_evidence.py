"""Arrange real viewport captures; no retouching of rendered content."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parents[2] / "docs/validation/player-v020-ragdoll"
font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 22)
small = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 18)

def sheet(filename, names, phases):
    width, height = 560, 440
    canvas = Image.new("RGB", (width * len(phases), 65 + height * len(names)), "#19212a")
    draw = ImageDraw.Draw(canvas)
    draw.text((18, 15), "PLAYER v020 | Godot 4.7.2 / Jolt | isolated ragdoll acceptance", font=font, fill="white")
    for row, name in enumerate(names):
        for col, phase in enumerate(phases):
            shot = Image.open(OUT / f"{name}_{phase}.png").convert("RGB")
            shot.thumbnail((width, height - 28))
            x, y = col * width, 65 + row * height
            canvas.paste(shot, (x + (width - shot.width) // 2, y))
            draw.text((x + 12, y + height - 26), f"{name} | {phase}", font=small, fill="white")
    canvas.save(OUT / filename)

sheet("falls_comparison.png", ["drop_face", "drop_back", "drop_right"], ["start", "settled", "recovered"])
sheet("terrain_comparison.png", ["slope", "stairs", "crouch_transition"], ["start", "settled", "recovered"])
sheet("standing_comparison.png", ["stand_forward", "stand_back", "stand_left", "animation_transition"], ["start", "settled", "recovered"])
