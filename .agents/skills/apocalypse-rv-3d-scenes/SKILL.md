---
name: apocalypse-rv-3d-scenes
description: Always read this skill first before building or editing ApocalypseRV 3D scenes and replacing visual assets.
---

# 3D Scene Creation

- **Finish simple objects directly:** For walls, floors and other objects that need only a few meshes and materials, complete their visuals and function without writing a modeling document.
- **Prepare a modeling request for complex objects:** For decor, props, equipment, or other assets whose detailed shape would require many small meshes, first write a short request so the user can later produce a reference image and use an image-to-3D diffuser to create the model. If the scene needs to function before delivery, graybox the necessary volume, openings, collision, and interactions. Do not assemble a finished asset from many small placeholder parts. Finish simple parts of the same scene as usual.
- **Split large buildings into modelable components where useful:** Complex facade sections, entrance assemblies, roof equipment, and interior fittings can each have their own request; a request does not have to cover an entire building. Choose boundaries that allow each component to be generated and replaced independently, while keeping the building layout and assembly in the Godot scene. Record the parent building, target node, local placement and orientation, and any adjoining dimensions or openings needed for a fit. Use building-and-component names such as `shelter-entrance` for request folders. Repeated instances of the same component share one request; simple structural parts still follow the direct-completion rule.

## Blender MCP

Blender MCP can be used for modeling, editing, inspecting, and exporting assets when the required tools are available and connected.

If Blender MCP is unavailable or cannot connect, ask the user to open Blender and enable its Blender MCP connection, explaining the observed limitation. 

## Image-to-3D Modeling Request

When preparing or updating a modeling request for a complex object, use [apocalypse-rv-image-to-3d-request](../apocalypse-rv-image-to-3d-request/SKILL.md). That skill defines the request format, reference-image handoff, model interfaces, delivery locations, and status updates.
