# Original industrial horror materials

Generated with the built-in `image_gen` tool on 2026-09-17, then copied into this project. Original source bitmaps remain unmodified. Godot import limits runtime textures to 512 pixels and generates mipmaps; materials use nearest sampling with mipmaps to keep close detail chunky without distant shimmer.

- `worn_paint.png`: neutral worn paint, tinted by RV and exterior materials. Original generated output: `exec-ffb4bc5a-d94b-4d1d-a94e-416ef9e1e7cd.png`.
- `forest_floor.png`: muted mud, gravel, leaf litter. Terrain samples at two world-space scales to break repetition. Original generated output: `exec-bf704ee9-577c-4641-861c-16fac02841ce.png`.
- Vegetation and mineral surfaces use cached 256px seamless NoiseTexture2D resources from `IndustrialArt`; these are deterministic procedural materials, not downloaded textures. Trees use one UV-sampled material with per-vertex bark/leaf colors, avoiding three-way projection and obvious elongated bark stripes across the foliage.

## Exact generation prompts

### Paint

Use case: stylized-concept. Asset type: seamless square albedo texture for an original low-resolution industrial horror 3D game. Generate a single seamless tile of old painted industrial steel, neutral warm light gray paint with restrained charcoal pits, irregular chipped paint exposing darker gray metal and subtle gray-brown oxidized stains. Flat orthographic surface fills entire image. Broad patchy wear, small sparse scratches, restrained simple hand-painted chunky shapes, readable when reduced to 256 pixels. Overall mid-light value, no black dominant patches, no directional lighting, no baked highlights, no shadows, no objects, no bolts, no panel seams, no borders, no letters or symbols. All four edges must tile. Original bitmap material, not a rendered scene or texture preview sheet. 1024x1024 square.

### Forest floor

Use case: stylized-concept. Asset type: single seamless square ground albedo tile for an original low-poly industrial horror game. Flat overhead forest floor: compacted gray-brown mud, small dull gravel, scattered decomposing narrow pine needles and leaf fragments. Muted neutral taupe midtone (not nearly black), broad irregular patches, hand-painted restrained chunky low-resolution texture, readable at 256px, no dense grain. Uniform diffuse color only, no shadows, no lighting gradient, no perspective, no objects larger than a palm, no grass tufts, no text, no borders. Opposite edges tile seamlessly. 1024x1024.

## Usage constraints

Exterior overrides never mutate the POI material resources shared by indoor scenes. Status lamps and transparent glass keep their separate original materials. Panel and engine damage adds a multiply detail layer over the base texture; repairing removes that extra layer rather than making old equipment factory-new.
