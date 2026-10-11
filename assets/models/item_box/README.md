# Industrial item box

Hand-authored precision mesh, with the scrapper/fabricator equipment palette: teal painted panels, orange lid guards and catches, dark corner bumpers, steel hardware. The deterministic 512 px PBR textures use the existing [scrapper material source](../../../art_source/scrapper/build_scrapper.py). No generated-image or ComfyUI assets.

- Centre origin, +Y up, catches face -Z. Geometry stays within the original 1.0 x 0.6 x 0.7 m collision envelope; feet reach Y=-0.3 m.
- 4,424 triangles / five material surfaces, within a 5,000-triangle budget for a metre-wide prop viewed at arm's length. Godot generates additional LODs.
- GLB contains the original mesh and embedded albedo, metallic/roughness and normal images. Keep import image handling on embedded to avoid duplicate extracted textures.
- `rv/visuals/item_box.tscn` owns the model instance. The equipment wrapper retains mass, collision, mount and storage behavior; its old primitive visuals and floating label are hidden.

2026-10-11 validation: Godot 4.7.2 Forward+ front/rear renders and the actual `starter_rv.tscn` installation were inspected. Collision size, mass, mounted support and local position assertions passed. Direct `test_rv_shared_storage` and `test_item_services` runs reached PASS, but both logged an unrelated missing `equipment/tablet_ui.tscn` in the concurrent working tree, so they are not clean regression passes. The standard runner was blocked by unrelated unclassified `test_rv_tablet_ui`. No manual gameplay or full suite was performed. Local authoring and review files remain ignored under `.godot/item_box_work/`.
