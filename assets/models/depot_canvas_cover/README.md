# Depot cargo canvas

Original editable Wavefront OBJ, metres, Y up. A single 192-triangle cloth sheet with UVs; rendered with the two-sided `world/orientation_shelter/materials/canvas.tres` material. No texture download, animation or embedded collision.

The top is a slightly rippled sheet above the wrapped cargo, with lowered side/end hems. Six instances in `building_details.tscn` sit at local Y=4.93 over 1.3 × 0.84 × 3.3 m wooden cargo blocks. Their box collisions live in `building_details_collision.tscn`. The cloth itself adds no solid obstruction to the search aisles.

Reviewed in the actual v12 warehouse with its existing lighting. This asset is native geometry, not a ComfyUI generation. The OBJ is the editable source; no authoring dependencies are needed at runtime.
