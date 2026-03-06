import os
import re

ROOT = "c:/Users/evan4/Projects/ApocalypseRV"

folders = {
    "scenes": [],
    "scripts": [],
    "tools": [],
    "assets": []
}

files_to_move = {
    # Scenes
    "rv.tscn": "scenes/rv.tscn",
    "player.tscn": "scenes/player.tscn",
    "driver_seat.tscn": "scenes/driver_seat.tscn",
    "test_world.tscn": "scenes/test_world.tscn",
    "house.tscn": "scenes/house.tscn",
    
    # Scripts
    "rv.gd": "scripts/rv.gd",
    "player.gd": "scripts/player.gd",
    "driver_seat.gd": "scripts/driver_seat.gd",
    "player_interact.gd": "scripts/player_interact.gd",
    
    # Tools
    "build_scenes.gd": "tools/build_scenes.gd",
    "build_test_world.gd": "tools/build_test_world.gd",
    "build_house.gd": "tools/build_house.gd",
    "generate_scenes.gd": "tools/generate_scenes.gd",
    "update_collisions.gd": "tools/update_collisions.gd",
    "run_update_collisions.gd": "tools/run_update_collisions.gd",
    "rebuild_user_rv.gd": "tools/rebuild_user_rv.gd",
    
    # Assets
    "icon.svg": "assets/icon.svg",
    "icon.svg.import": "assets/icon.svg.import"
}

# Add .uid files
uids = {}
for k, v in files_to_move.items():
    if os.path.exists(os.path.join(ROOT, k + ".uid")):
        uids[k + ".uid"] = v + ".uid"

files_to_move.update(uids)

# Replacements
replacements = {}
for k, v in files_to_move.items():
    if k.endswith(".gd") or k.endswith(".tscn") or k.endswith(".svg"):
        replacements[f"res://{k}"] = f"res://{v}"

print("Replacements:", replacements)

# Create folders
for f in folders:
    os.makedirs(os.path.join(ROOT, f), exist_ok=True)

# Update all .tscn and .gd files
for root, _, files in os.walk(ROOT):
    for file in files:
        if file.endswith(".gd") or file.endswith(".tscn"):
            filepath = os.path.join(root, file)
            with open(filepath, "r", encoding="utf-8") as f:
                content = f.read()
            
            new_content = content
            for old_str, new_str in replacements.items():
                new_content = new_content.replace(old_str, new_str)
            
            if new_content != content:
                print(f"Updated {file}")
                with open(filepath, "w", encoding="utf-8") as f:
                    f.write(new_content)

# Move files
import shutil
for k, v in files_to_move.items():
    src = os.path.join(ROOT, k)
    dst = os.path.join(ROOT, v)
    if os.path.exists(src):
        shutil.move(src, dst)
        print(f"Moved {k} -> {v}")

print("Done organizing.")
