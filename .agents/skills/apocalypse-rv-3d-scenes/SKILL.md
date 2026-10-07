---
name: apocalypse-rv-3d-scenes
description: Always read this skill first before building or editing ApocalypseRV 3D scenes and replacing visual assets.
---

# 3D Scene Creation

- **Finish simple objects directly:** Complete walls, floors and other objects that need only a few meshes and materials, including their visuals and function.
- **Generate suitable visuals with ComfyUI:** Use [comfyui-image-to-3d](../comfyui-image-to-3d/SKILL.md) for suitable static props, decor and equipment. The main agent handles reference creation, generation, inspection, refinement and integration directly. Use native meshes for precise structure, layout, collision and interaction; graybox where needed while producing the visual.
- **Split large buildings into components where useful:** Generate or model facade sections, entrance assemblies, roof equipment and interior fittings separately. Keep the building layout and assembly in Godot, with each component independently replaceable. Track the target node, local placement, orientation and adjoining dimensions or openings needed for a fit. Repeated instances share one asset; finish simple structural parts directly.
- **Verify visual replacements in context:** Check local axes, origin, design dimensions and placement in the target scene. Preserve the existing wrapper tree, collision and gameplay behavior when replacing visuals. Graybox placement alone does not establish a finished visual result; inspect the actual integrated asset.
- **Evaluate rendering cost before delivery:** Choose a triangle budget for the object's size, viewing distance and expected instance count. Try reduction when the generated mesh is unnecessarily dense; compare the result visually and explain the choice if keeping a higher count. Generation defaults and automatic LOD do not establish an asset budget.

## Blender MCP

Blender MCP can be used for modeling, editing, inspecting, and exporting assets when the required tools are available and connected.

If Blender MCP is unavailable, use existing offline CLI, glTF or Godot tools when they can complete the task. Ask the user to open Blender and enable its MCP connection only when the task requires Blender and available alternatives cannot complete it; explain the observed limitation.

## Image-to-3D Workflow

Follow [comfyui-image-to-3d](../comfyui-image-to-3d/SKILL.md) directly for image-to-3D work. Preserve the raw model, inspect and refine the result, then verify it in the target scene. Report remaining problems briefly. Do not require a modeling request document before starting; prepare a handoff only when the task needs one.
