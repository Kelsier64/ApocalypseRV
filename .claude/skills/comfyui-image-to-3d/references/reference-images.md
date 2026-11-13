# Reference images via agy (Gemini)

Claude has no image generator, and local ComfyUI has no text-to-image model. When no existing image fits, have Antigravity CLI draw one: its `image-generator` subagent paints the image, and agy removes the background itself. Read the user-level `agy` skill for locating the binary and general flags.

## Call

Run it in a fresh, empty folder **outside the repository**. `--mode auto` lets agy run its background-removal step; `accept-edits` blocks that step and ends early. One image takes about 4–5 minutes, so launch with `run_in_background`:

```powershell
$agy = (Get-Command agy -ErrorAction SilentlyContinue).Source; if (-not $agy) { $agy = "$env:LOCALAPPDATA\agy\bin\agy.exe" }
$ref = "$env:TEMP\agy-ref-<asset>"; New-Item -ItemType Directory -Force $ref | Out-Null; Push-Location $ref
$p = "Generate an image and save it in the current directory as <asset>.png. Subject: <object, materials, wear, colors>. Single complete object, three-quarter view with weak perspective, camera near horizontal, isolated on a fully transparent background (real alpha channel, not a checkerboard), no floor, no shadow, no text or labels. Do not end your turn until the image generation has finished and <asset>.png exists on disk; wait for any subagent result. Then report the saved absolute path. Do nothing else."
& $agy -p $p --output-format json --mode auto --sandbox --print-timeout 480s 2>$null | Out-String
Pop-Location
```

Without the "do not end your turn" sentence, print mode returns as soon as the subagent starts and nothing is written.

## Check before use

1. Verify a real alpha channel, not a painted checkerboard:

   ```powershell
   & $py -I -c "import sys;from PIL import Image;im=Image.open(sys.argv[1]);a=im.getchannel('A') if 'A' in im.getbands() else None;print(im.size,im.mode,a.getextrema() if a else 'NO ALPHA')" "$ref/<asset>.png"
   ```

   Expect `RGBA` and alpha `(0, 255)`. If there is no alpha, ask agy to remove the background (`--conversation <id>`), or regenerate.
2. Read the image with the Read tool against the requirements in [SKILL.md](../SKILL.md#1-reference-image): one object, clean edges, no text, no floor or shadow, thin parts (chains, wires) thick enough or planned as separate geometry.
3. If it fails, follow up in the same conversation with `--conversation <id>` and name the specific fix, rather than starting over.

Copy the accepted image to `art_source/<asset>/reference.png` and record the prompt in the asset README. Delete the temp folder afterward.
