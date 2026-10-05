"""Regression tests for cross-view camera scale and background treatment."""
import io
import unittest
from PIL import Image, ImageDraw
from pipeline import InputError, prepare_inputs, build_workflow


def png(image):
    output = io.BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


def panels(alpha=False):
    images = {}
    for name, width in [("front", 240), ("left", 110), ("back", 240)]:
        image = Image.new("RGBA" if alpha else "RGB", (300, 300), (255, 255, 255, 0) if alpha else (0, 0, 0))
        ImageDraw.Draw(image).rectangle(((300-width)//2, 30, (300+width)//2, 270), fill=(170, 170, 170, 255) if alpha else (170, 170, 170))
        images[name] = image
    return images


class PipelineTests(unittest.TestCase):
    def test_alpha_respects_original_camera_scale_and_empty_rgb(self):
        source = panels(alpha=True)
        prepared = prepare_inputs({name: png(image) for name, image in source.items()}, "threeview1024")
        bboxes = [Image.open(io.BytesIO(prepared.images[name])).getbbox() for name in source]
        self.assertLess(abs((bboxes[0][3]-bboxes[0][1])-(bboxes[1][3]-bboxes[1][1])), 2)
        self.assertLess(bboxes[1][2]-bboxes[1][0], .5 * (bboxes[0][2]-bboxes[0][0]))
        self.assertEqual(Image.open(io.BytesIO(prepared.images["front"])).getpixel((0, 0)), (0, 0, 0))
        self.assertEqual(prepared.metadata["original_background_modes"]["front"], "alpha")

    def test_sheet_equals_separate_views(self):
        source = panels()
        sheet = Image.new("RGB", (900, 300))
        for index, image in enumerate(source.values()):
            sheet.paste(image, (index*300, 0))
        a = prepare_inputs({"image": png(sheet)}, "threeview512")
        b = prepare_inputs({name: png(image) for name, image in source.items()}, "threeview512")
        self.assertEqual(a.images, b.images)

    def test_rejects_non_square_layout_before_generation(self):
        for width in (899, 901, 600):
            with self.assertRaises(InputError):
                prepare_inputs({"image": png(Image.new("RGB", (width, 300)))}, "threeview512")
        source = {name: png(image) for name, image in panels().items()}
        source["left"] = png(Image.new("RGB", (200, 200)))
        with self.assertRaises(InputError):
            prepare_inputs(source, "threeview512")

    def test_shared_canvas_graph_has_no_crop_or_fit(self):
        prepared = prepare_inputs({name: png(image) for name, image in panels().items()}, "threeview1024", fov=24)
        graph = build_workflow("threeview1024", {name: name+'.png' for name in prepared.images}, prepared.metadata, "test/job")
        self.assertFalse(any(node["class_type"] in ("ImageCropToMask", "ImageCrop") for node in graph.values()))
        self.assertEqual(graph["298"]["inputs"]["fov"], 24)
        self.assertEqual(len([node for node in graph.values() if node["class_type"] == "SaveImage"]), 3)

    def test_opaque_white_inputs_get_matting_without_camera_resize(self):
        source = panels()
        for image in source.values():
            ImageDraw.Draw(image).rectangle((0, 0, 10, 299), fill="white")
        prepared = prepare_inputs({name: png(image) for name, image in source.items()}, "threeview512")
        self.assertEqual(set(prepared.metadata["background_modes"].values()), {"remove"})
        graph = build_workflow("threeview512", {name: name+'.png' for name in prepared.images}, prepared.metadata, "test/job")
        composites = [node for node in graph.values() if node["class_type"] == "ImageCompositeMasked"]
        self.assertEqual(len(composites), 3)
        self.assertTrue(all(not node["inputs"]["resize_source"] for node in composites))
        self.assertFalse(any(node["class_type"] == "ImageCropToMask" for node in graph.values()))

    def test_single_alpha_avoids_second_background_model(self):
        prepared = prepare_inputs({"image": png(panels(alpha=True)["front"])}, "standard1024", fov=20)
        graph = build_workflow("standard1024", {"image": "front.png"}, prepared.metadata, "test/job")
        self.assertFalse(any(node["class_type"] in ("RemoveBackground", "LoadMoGeModel") for node in graph.values()))
        self.assertEqual(graph["298"]["inputs"]["camera_angle_x"], 20)

    def test_validates_fov_corrupt_inputs_and_empty_alpha(self):
        for fov in (0, 171, float("nan"), float("inf")):
            with self.assertRaises(InputError):
                prepare_inputs({"image": png(panels()["front"])}, "preview512", fov)
        for raw in (b"not PNG", png(Image.new("RGBA", (300,300), (255,255,255,0)))):
            with self.assertRaises(InputError):
                prepare_inputs({"image": raw}, "preview512")


if __name__ == "__main__":
    unittest.main()
