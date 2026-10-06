---
name: apocalypse-rv-3d-scenes
description: Always read this skill first before building or editing ApocalypseRV 3D scenes and replacing visual assets.
---

# 3D Scene Creation

- **Finish simple objects directly:** For walls, floors and other objects that need only a few meshes and materials, complete their visuals and function without writing a modeling document.
- **Create suitable complex visuals directly:** Use [comfyui-image-to-3d](../comfyui-image-to-3d/SKILL.md) for static props, decor and equipment that benefit from image-to-3D. The main agent can generate, inspect, edit and integrate the result without a modeling handoff. Use native meshes for precise structure, layout, collision and interaction; graybox where needed while producing the visual.
- **Split large buildings into modelable components where useful:** Complex facade sections, entrance assemblies, roof equipment, and interior fittings can be generated or modeled separately; create requests only when a handoff is useful. Choose boundaries that allow each component to be generated and replaced independently, while keeping the building layout and assembly in the Godot scene. Record the parent building, target node, local placement and orientation, and any adjoining dimensions or openings needed for a fit. Use building-and-component names such as `shelter-entrance` for request folders. Repeated instances of the same component share one asset; simple structural parts still follow the direct-completion rule.

## Blender MCP

Blender MCP can be used for modeling, editing, inspecting, and exporting assets when the required tools are available and connected.

If Blender MCP is unavailable or cannot connect, ask the user to open Blender and enable its Blender MCP connection, explaining the observed limitation. 

## Image-to-3D Modeling Request

When a modeling request or handoff is useful, use [apocalypse-rv-image-to-3d-request](../apocalypse-rv-image-to-3d-request/SKILL.md). That skill defines the request format, reference-image handoff, model interfaces, delivery locations, and status updates.
