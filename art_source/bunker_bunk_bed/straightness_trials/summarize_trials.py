"""Compose QA screenshots and collect experiment diagnostics; does not edit art."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

BASE = Path(__file__).resolve().parent
CASES = [
    ('original_fitted', 'Original reference + old fit'),
    ('level_1024', 'Level single view / auto FOV / 1024'),
    ('level_fov20_1024', 'Level single view / FOV 20 / 1024'),
    ('mv_api_v2_1024', '3 views / API individual crops / 1024'),
    ('mv_fixed_512', '3 views / shared canvas / 512'),
    ('mv_fixed_1024', '3 views / shared canvas / 1024 / seed 42'),
    ('mv_fixed_1024_seed43', '3 views / shared canvas / 1024 / seed 43'),
]

font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 22)
small = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 17)
sheet = Image.new('RGB', (1080, len(CASES) * 390 + 38), (24, 29, 35))
draw = ImageDraw.Draw(sheet)
for i, view in enumerate(['FRONT (orthographic)', 'SIDE (orthographic)', 'OBLIQUE']):
    draw.text((i * 360 + 10, 9), view, font=small, fill='white')
summary = []
for row, (case, label) in enumerate(CASES):
    folder = BASE / case
    y = 38 + row * 390
    draw.text((10, y), label, font=font, fill='white')
    for column, view in enumerate(['front', 'side', 'oblique']):
        screenshot = Image.open(folder / 'review' / (view + '.png')).convert('RGB')
        screenshot.thumbnail((360, 360))
        sheet.paste(screenshot, (column * 360, y + 30))
    measurements = json.loads((folder / 'measurements.json').read_text())
    stats = json.loads((folder / 'review' / 'godot_review.json').read_text())
    summary.append({'case': case, 'label': label, 'measurements': measurements, 'render': stats})
sheet.save(BASE / 'comparison.png')
(BASE / 'comparison.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps({'rendered_cases': len(CASES), 'comparison': str(BASE / 'comparison.png')}))
