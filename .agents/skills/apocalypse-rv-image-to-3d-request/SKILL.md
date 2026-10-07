---
name: apocalypse-rv-image-to-3d-request
description: Create or update ApocalypseRV modeling requests for the user's reference-image and image-to-3D diffuser workflow. Use for complex assets that need a modeling handoff; not for simple mesh construction or logic-only changes.
---

# Image-to-3D Modeling Request

Use this skill when a request or modeling handoff is useful or explicitly requested. For direct generation and use, follow [comfyui-image-to-3d](../comfyui-image-to-3d/SKILL.md) without creating a handoff. When writing a request, create `docs/modeling/requests/<name>/`, then write its single request at `docs/modeling/requests/<name>/<name>.md`; the [short template](../../../docs/modeling/TEMPLATE.md) is available. This request is the handoff for the user's reference-image and image-to-3D workflow. Include a concise visual description that can be used to produce the reference image, plus the scene or node it will replace, its dimensions and orientation, and delivery location. Keep reference images in the same folder and link them from the request when available; writing a request alone does not require generating an image. Use meters and specify the origin and facing direction. Label measured values, design values, and unconfirmed details accurately.

For moving parts, sockets, or skeletal animation, record only the interfaces the game needs. Treat part separation, pivots, rigging, and animations as follow-up modeling or integration work where needed; do not assume the diffuser output already satisfies these requirements.

Update the same request when requirements or completion status change; a one-sentence progress note is enough. Do not maintain a separate queue, specification versions, or global manifest, and do not automatically assign work to or wait for a modeling AI merely because a request was written. For generation, use [comfyui-image-to-3d](../comfyui-image-to-3d/SKILL.md); the main agent can create the reference, generate, inspect, edit and integrate directly. Delegate only when useful for the task. Continue scene work using the graybox where needed, then replace the visuals with the checked result. Inventory, planning, or archiving work alone does not automatically create modeling requests.

Usually place delivered GLBs and textures in `assets/models/<name>/` and editable sources in `art_source/<name>/`; keep an existing location when there is one. Record provenance and licensing in the asset's README when needed.
