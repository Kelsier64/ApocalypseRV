---
name: apocalypse-rv-3d-scenes
description: Always read this skill first before building or editing ApocalypseRV 3D scenes and replacing visual assets.
---

# 3D Scene Creation

By default, follow “necessary production → one contextual review → relevant validation → concise report.” For small changes, perform only localized checks; expand or rerun checks only when there are new changes, failures, or unresolved concerns. Add scripts, delegation, lengthy reports, or delivery packages only when necessary or requested by the user.


- **Finish simple objects directly:** Complete walls, floors and other objects that need only a few meshes and materials, including their visuals and function.
- **Generate suitable visuals with ComfyUI:** Use [comfyui-image-to-3d](../comfyui-image-to-3d/SKILL.md) for suitable static props, decorations, crates, barrels, components, equipment, and objects with clear silhouettes where approximate details are acceptable. Use native meshes for precise structure, layout, collision and interaction.
- **Split large buildings into components where useful:** Generate or model facade sections, entrance assemblies, roof equipment and interior fittings separately. Keep the building layout and assembly in Godot, with each component independently replaceable. Track the target node, local placement, orientation and adjoining dimensions or openings needed for a fit. Repeated instances share one asset; finish simple structural parts directly.
- **Verify visual replacements in context:** Check local axes, origin, design dimensions and placement in the target scene. Preserve the existing wrapper tree, collision and gameplay behavior when replacing visuals. Graybox placement alone does not establish a finished visual result; inspect the actual integrated asset.
- **No model prompts:** Never place gameplay hints, controls, instructions, item names, or status labels on models, textures, or in the 3D world. Do not use `Label3D`, `TextMesh`, floating, camera-facing, white/glowing, or unshaded text as model presentation. Interaction prompts belong in screen-space UI.
- **World text only as justified game art:** Add words only where they clearly belong in the fiction and serve the object, such as an essential physical sign, manufacturer plate, or actual instrument screen. Use an authored texture/decal or the device screen, with appropriate lighting, wear, scale, and placement. Do not add decorative wording by default, disguise gameplay hints as texture art, or let scene generators restore removed labels. Reference images and generated assets must follow the same rule.

## Blender MCP

Blender MCP can be used for modeling, editing, inspecting, and exporting assets when the required tools are available and connected.

If Blender MCP is unavailable, use existing offline CLI, glTF or Godot tools when they can complete the task. Ask the user to open Blender and enable its MCP connection only when the task requires Blender and available alternatives cannot complete it; explain the observed limitation.
