---
name: apocalypse-rv-3d-scenes
description: Build or integrate ApocalypseRV Godot 3D scenes, RV parts, equipment, terrain props, and replacement meshes or materials.
---

# ApocalypseRV 3D Scenes

- Build shells, openings, moving joints, and collision directly with precise geometry. Use `apocalypse-rv-image-to-3d` for props with clear silhouettes and room for approximation. Use generated meshes as visual shells when structure needs exact dimensions.
- Keep large structures modular. Record target node, placement, orientation, and adjoining dimensions. Instance shared assets for repeated pieces.
- Preserve wrapper names, collision, and interaction when replacing a placeholder. Verify axes, origin, scale, and lighting in the real scene. Use `apocalypse-rv-playtest` for a gameplay-camera render.
- For 3D textures, verify `mipmaps/generate=true` in import settings and reimport if needed. Follow the [project text rules](../../../AGENTS.md#project-rules).
- Use Blender's background CLI for scripted inspection, remeshing, baking, and export. Use the Codex Blender MCP for live work on an open scene. Keep scratch scripts and captures under `.godot/`.
