"""Pixal3D input preparation and pinned workflow construction.

Multi-view input cameras share a canvas. Never independently crop or fit a view.
Alpha is authoritative; opaque photographs are matted without reframing them.
"""
import hashlib
import io
import json
import math
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageOps, UnidentifiedImageError

PRESETS = ("preview512", "standard1024", "threeview512", "threeview1024")
VIEWS = ("front", "left", "back", "right")
ROOT = Path(__file__).resolve().parent
MAX_PIXELS = 16_777_216


class InputError(ValueError):
    def __init__(self, detail, status_code=422):
        super().__init__(detail)
        self.detail = detail
        self.status_code = status_code


@dataclass
class PreparedInputs:
    images: dict[str, bytes]
    metadata: dict


def decode(raw):
    if len(raw) > 25 * 1024 * 1024:
        raise InputError("Each image must be at most 25 MiB", 413)
    try:
        with Image.open(io.BytesIO(raw)) as image:
            if image.width * image.height > MAX_PIXELS:
                raise InputError("Image exceeds 16 megapixels", 413)
            if getattr(image, "is_animated", False):
                raise InputError("Upload a still image, not an animation")
            image.load()
            image = ImageOps.exif_transpose(image).convert("RGBA")
            if min(image.size) < 64 or max(image.size) > 8192:
                raise InputError("Image edges must be 64-8192 pixels")
            if image.getchannel("A").getextrema()[1] == 0:
                raise InputError("Image is completely transparent")
            return image
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as error:
        if isinstance(error, InputError):
            raise
        raise InputError("Unreadable image") from error


def background_mode(image, requested):
    alpha_min, alpha_max = image.getchannel("A").getextrema()
    has_alpha = alpha_min < alpha_max or alpha_max < 255
    if requested == "alpha":
        if not has_alpha:
            raise InputError("background=alpha requires a non-opaque alpha channel")
        return "alpha"
    if requested == "remove":
        return "remove"
    if has_alpha:
        return "alpha"
    if requested == "black":
        return "black"
    # Auto only calls a canvas black if its border is consistently dark.
    rgb = image.convert("RGB")
    edge = [rgb.getpixel((x, y)) for x in (0, rgb.width - 1) for y in range(0, rgb.height, max(1, rgb.height // 32))]
    edge += [rgb.getpixel((x, y)) for y in (0, rgb.height - 1) for x in range(0, rgb.width, max(1, rgb.width // 32))]
    return "black" if max(max(pixel) for pixel in edge) <= 20 else "remove"


def encode(image):
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def prepare_inputs(raw_images, preset, fov=None, background="auto"):
    if preset not in PRESETS:
        raise InputError("Unsupported preset")
    if background not in ("auto", "alpha", "black", "remove"):
        raise InputError("background must be auto, alpha, black or remove")
    if fov is not None and (not math.isfinite(fov) or not 1 <= fov <= 170):
        raise InputError("fov must be finite and between 1 and 170 degrees")
    if not raw_images or set(raw_images) - {"image", *VIEWS}:
        raise InputError("Unexpected image fields")
    multiview = preset.startswith("threeview")
    decoded = {name: decode(raw) for name, raw in raw_images.items()}
    source_dimensions = {name: list(image.size) for name, image in decoded.items()}
    if multiview:
        if set(decoded) == {"image"}:
            sheet = decoded["image"]
            if sheet.width != 3 * sheet.height:
                raise InputError("Three-view sheet must be exactly 3:1: three equal square panels, front / left / back. Use /jobs/multiview for separate square views.")
            side = sheet.height
            decoded = {name: sheet.crop((index * side, 0, (index + 1) * side, side)) for index, name in enumerate(VIEWS[:3])}
        elif not {"front", "left", "back"}.issubset(decoded) or "image" in decoded:
            raise InputError("Multi-view requires front, left and back, plus optional right")
        sizes = {image.size for image in decoded.values()}
        if len(sizes) != 1 or any(image.width != image.height for image in decoded.values()):
            raise InputError("All views must use the same square canvas and physical pixel scale; independent fitting is not allowed")
        if next(iter(sizes))[0] > 4096:
            raise InputError("Each multi-view panel must be at most 4096 pixels")
    elif set(decoded) != {"image"}:
        raise InputError("Single-image preset requires exactly one image")
    elif max(decoded["image"].size) > 4096:
        raise InputError("Single-image edges must be at most 4096 pixels")
    images = {}
    effective = {}
    original_modes = {}
    bounds = {}
    dimensions = {}
    for name, image in decoded.items():
        mode = background_mode(image, background)
        original_modes[name] = mode
        if multiview:
            if mode == "alpha":
                image = Image.alpha_composite(Image.new("RGBA", image.size, (0, 0, 0, 255)), image).convert("RGB")
                mode = "black"
            else:
                image = image.convert("RGB")
            # Equal square canvases => one shared scale. Never fit silhouettes.
            image = image.resize((1024, 1024), Image.Resampling.LANCZOS)
        dimensions[name] = list(image.size)
        bounds[name] = list(image.convert("RGB").getbbox() or ())
        images[name] = encode(image)
        effective[name] = mode
    template = ROOT / "workflows" / (preset + ".json")
    revision = hashlib.sha256(Path(__file__).read_bytes() + template.read_bytes()).hexdigest()
    return PreparedInputs(images, {
        "mode": "multiview" if multiview else "single", "preset": preset,
        "fov": (20.0 if fov is None else float(fov)) if multiview else fov,
        "framing": "shared_square_canvas" if multiview else "single_object_crop",
        "source_dimensions": source_dimensions, "prepared_dimensions": dimensions,
        "input_sha256": {name: hashlib.sha256(raw).hexdigest() for name, raw in raw_images.items()},
        "original_background_modes": original_modes, "background_modes": effective,
        "prepared_rgb_bounds": bounds, "workflow_revision": "shared-frame-v2:" + revision,
    })


def prune_graph(graph, outputs):
    keep, todo = set(outputs), list(outputs)
    while todo:
        for value in graph[todo.pop()]["inputs"].values():
            if isinstance(value, list) and len(value) == 2 and isinstance(value[0], str) and value[0] in graph and value[0] not in keep:
                keep.add(value[0])
                todo.append(value[0])
    return {key: node for key, node in graph.items() if key in keep}


def build_workflow(preset, input_files, metadata, artifact_prefix):
    graph = json.loads((ROOT / "workflows" / (preset + ".json")).read_text(encoding="utf-8"))
    outputs = ["save"]
    if metadata["mode"] == "multiview":
        # Delete every legacy per-view crop/fit/matting node, including unused
        # nodes, so the saved workflow unambiguously represents shared cameras.
        image_types = {"ImageCrop", "ImageCropToMask", "RemoveBackground", "LoadImage", "LoadBackgroundRemovalModel"}
        graph = {key: node for key, node in graph.items() if node["class_type"] not in image_types}
        graph["298"]["inputs"]["fov"] = metadata["fov"]
        for name in VIEWS:
            graph["298"]["inputs"].pop(name, None)
        for name, filename in input_files.items():
            loader = "v2_load_" + name
            graph[loader] = {"class_type": "LoadImage", "inputs": {"image": filename}}
            frame = [loader, 0]
            if metadata["background_modes"][name] == "remove":
                graph["v2_bg_model"] = {"class_type": "LoadBackgroundRemovalModel", "inputs": {"bg_removal_name": "birefnet.safetensors"}}
                graph["v2_black"] = {"class_type": "EmptyImage", "inputs": {"width": 1024, "height": 1024, "batch_size": 1, "color": 0}}
                graph["v2_mask_" + name] = {"class_type": "RemoveBackground", "inputs": {"bg_removal_model": ["v2_bg_model", 0], "image": frame}}
                composite = "v2_frame_" + name
                graph[composite] = {"class_type": "ImageCompositeMasked", "inputs": {"destination": ["v2_black", 0], "source": frame, "mask": ["v2_mask_" + name, 0], "x": 0, "y": 0, "resize_source": False}}
                frame = [composite, 0]
            graph["298"]["inputs"][name] = frame
            output = "conditioning_" + name
            graph[output] = {"class_type": "SaveImage", "inputs": {"images": frame, "filename_prefix": artifact_prefix + "/conditioning/" + name}}
            outputs.append(output)
    else:
        graph["122"]["inputs"]["image"] = input_files["image"]
        if metadata["background_modes"]["image"] == "alpha":
            graph["v2_alpha"] = {"class_type": "InvertMask", "inputs": {"mask": ["122", 1]}}
            graph["312"]["inputs"]["masks"] = ["v2_alpha", 0]
        if metadata["fov"] is not None:
            graph["298"]["inputs"]["camera_angle_x"] = metadata["fov"]
        graph["conditioning_image"] = {"class_type": "SaveImage", "inputs": {"images": ["312", 0], "filename_prefix": artifact_prefix + "/conditioning/image"}}
        outputs.append("conditioning_image")
    graph["save"]["inputs"]["filename_prefix"] = artifact_prefix + "/model"
    return prune_graph(graph, outputs)
