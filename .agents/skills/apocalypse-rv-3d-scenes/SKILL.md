---
name: apocalypse-rv-3d-scenes
description: Build or edit ApocalypseRV 3D scenes and replace visual assets. Finish simple objects directly; prepare modeling requests for complex building components, decor, props, and equipment that the user will create with an image-to-3D diffuser, using grayboxes where needed. Not for logic-only changes.
---

# 3D Scene Creation

Prefer reusing existing models and materials. Keep finished visuals already in use; do not replace them with grayboxes just to follow this workflow.

- **Finish simple objects directly:** For walls, floors and other objects that need only a few meshes and materials, complete their visuals and function without writing a modeling document.
- **Prepare a modeling request for complex objects:** For decor, props, equipment, or other assets whose detailed shape would require many small meshes, first write a short request so the user can later produce a reference image and use an image-to-3D diffuser to create the model. If the scene needs to function before delivery, graybox the necessary volume, openings, collision, and interactions. Do not assemble a finished asset from many small placeholder parts. Finish simple parts of the same scene as usual.
- **Split large buildings into modelable components where useful:** Complex facade sections, entrance assemblies, roof equipment, and interior fittings can each have their own request; a request does not have to cover an entire building. Choose boundaries that allow each component to be generated and replaced independently, while keeping the building layout and assembly in the Godot scene. Record the parent building, target node, local placement and orientation, and any adjoining dimensions or openings needed for a fit. Use building-and-component names such as `shelter-entrance` for request folders. Repeated instances of the same component share one request; simple structural parts still follow the direct-completion rule.

## Image-to-3D Modeling Request

For each requested model, first create `docs/modeling/requests/<name>/`, then write its single request at `docs/modeling/requests/<name>/<name>.md`; the [short template](../../../docs/modeling/TEMPLATE.md) is available. This request is the handoff for the user's reference-image and image-to-3D workflow. Include a concise visual description that can be used to produce the reference image, plus the scene or node it will replace, its dimensions and orientation, and delivery location. Keep reference images in the same folder and link them from the request when available; writing a request alone does not require generating an image. Use meters and specify the origin and facing direction. Label measured values, design values, and unconfirmed details accurately.

For moving parts, sockets, or skeletal animation, record only the interfaces the game needs. Treat part separation, pivots, rigging, and animations as follow-up modeling or integration work where needed; do not assume the diffuser output already satisfies these requirements.

Update the same request when requirements or completion status change; a one-sentence progress note is enough. Do not maintain a separate queue, specification versions, or global manifest, and do not automatically assign work to or wait for a modeling AI. Continue scene work using the graybox where needed; import and replace the visuals when the user provides the model. Inventory, planning, or archiving work alone does not automatically create modeling requests.

Usually place delivered GLBs and textures in `assets/models/<name>/` and editable sources in `art_source/<name>/`; keep an existing location when there is one. Record provenance and licensing in the asset's README when needed.

## Replacement and Validation

When replacing visuals, preserve collision, interactions, and existing node interfaces, including sockets, skeletons, and animations used by the game. Do not change them merely to standardize names. Validate according to the actual change: for visuals alone, focus on import, visual inspection of scale and orientation, and related functions; expand regression testing only when behavior changes. For documentation-only changes, check formatting and links without running the full game suite.

Read specialized guides only when relevant: [characters and monsters](../../../docs/guides/character-modeling.md), [POIs](../../../docs/guides/poi-authoring.md), and [bunker rooms](../../../docs/guides/bunker-interior.md).
