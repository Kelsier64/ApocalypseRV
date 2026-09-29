---
name: apocalypse-rv-3d-scenes
description: Build or edit ApocalypseRV 3D scenes and replace visual assets. Finish simple mesh-and-material objects directly; use grayboxes and short modeling prompts for complex assets. Not for logic-only changes.
---

# 3D Scene Creation

Prefer reusing existing models and materials. Keep finished visuals already in use; do not replace them with grayboxes just to follow this workflow.

- **Finish simple objects directly:** For walls, floors, straight pipes, and other objects that need only a few meshes and materials, complete their visuals and function without writing a modeling document.
- **Use a graybox and short prompt for complex objects:** When an object needs a distinctive silhouette, dense mechanical detail, or rigging, first graybox the necessary volume, openings, and function. Do not assemble a finished asset from many small placeholder parts. Finish simple parts of the same scene as usual.

## Short Modeling Prompt

For each requested model, first create `docs/modeling/requests/<name>/`, then write its single prompt at `docs/modeling/requests/<name>/<name>.md`; the [short template](../../../docs/modeling/TEMPLATE.md) is available. Keep image-to-3D reference images generated for that request in the same folder. State what to build, the scene or node it will replace, its dimensions and orientation, visual requirements, and delivery location. Use meters and specify the origin and facing direction. Label measured values, design values, and unconfirmed details accurately. Include the necessary interfaces only when the asset has moving parts, sockets, or skeletal animation; omit irrelevant fields.

Update the same prompt when requirements or completion status change; a one-sentence progress note is enough. Do not maintain a separate queue, specification versions, or global manifest, and do not automatically assign work to or wait for a modeling AI. Inventory, planning, or archiving work alone does not automatically create modeling requests.

Usually place delivered GLBs and textures in `assets/models/<name>/` and editable sources in `art_source/<name>/`; keep an existing location when there is one. Record provenance and licensing in the asset's README when needed.

## Replacement and Validation

When replacing visuals, preserve collision, interactions, and existing node interfaces, including sockets, skeletons, and animations used by the game. Do not change them merely to standardize names. Validate according to the actual change: for visuals alone, focus on import, visual inspection of scale and orientation, and related functions; expand regression testing only when behavior changes. For documentation-only changes, check formatting and links without running the full game suite.

Read specialized guides only when relevant: [characters and monsters](../../../docs/guides/character-modeling.md), [POIs](../../../docs/guides/poi-authoring.md), and [bunker rooms](../../../docs/guides/bunker-interior.md).
