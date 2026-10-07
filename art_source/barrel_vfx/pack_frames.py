"""Pack Blender MCP volume renders; Pillow/numpy only, no simulation at runtime."""
from pathlib import Path
import numpy as np
from PIL import Image
ROOT = Path(__file__).resolve().parents[2]
FRAMES = ROOT / ".godot/art-work/barrel-vfx/realism/frames"
OUT = ROOT / "assets/effects/barrel_blast"
def linear(c):
    return np.where(c <= .04045, c / 12.92, ((c + .055) / 1.055) ** 2.4)
def srgb(c):
    return np.where(c <= .0031308, c * 12.92, 1.055 * np.maximum(c, 0) ** (1 / 2.4) - .055)
smoke_atlas = Image.new("RGBA", (2048, 2048))
fire_atlas = Image.new("RGBA", (2048, 2048))
for i in range(64):
    smoke = np.asarray(Image.open(FRAMES / f"smoke_{i:02}.png").convert("RGBA"), dtype=np.float32) / 255
    fire_base = np.zeros_like(smoke)
    beauty = np.zeros_like(smoke)
    if i < 24:
        fire_base = np.asarray(Image.open(FRAMES / f"fire_base_{i:02}.png").convert("RGBA"), dtype=np.float32) / 255
        beauty = np.asarray(Image.open(FRAMES / f"fire_beauty_{i:02}.png").convert("RGBA"), dtype=np.float32) / 255
    s = linear(fire_base[:,:,:3]) * fire_base[:,:,3:4]
    b = linear(beauty[:,:,:3]) * beauty[:,:,3:4]
    difference = np.maximum(b - s, 0)
    alpha = np.clip(np.max(difference / np.maximum(1 - s, 1e-4), axis=2, keepdims=True), 0, 1)
    # Straight-alpha foreground yielding the beauty when composited over soot.
    rgb = (b - s * (1 - alpha)) / np.maximum(alpha, 1e-5)
    rgb = np.clip(srgb(np.maximum(rgb, 0)), 0, 1)
    rgb[alpha[:,:,0] < .003] = 0
    alpha[alpha < .003] = 0
    fire = np.concatenate((rgb, alpha), axis=2)
    xy = ((i % 8) * 256, (i // 8) * 256)
    smoke_atlas.paste(Image.fromarray(np.uint8(np.clip(smoke, 0, 1) * 255 + .5)), xy)
    fire_atlas.paste(Image.fromarray(np.uint8(fire * 255 + .5)), xy)
smoke_atlas.save(OUT / "smoke_atlas.png", optimize=True)
fire_atlas.save(OUT / "fire_atlas.png", optimize=True)
print("Packed two 2048x2048 RGBA atlases, 64 frames each.")

