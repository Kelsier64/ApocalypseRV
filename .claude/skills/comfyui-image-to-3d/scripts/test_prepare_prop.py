"""Offline geometry/export/publish regression checks; no generation or game edits."""
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

import numpy as np

import prepare_prop as prop


class PropTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # A real generated asset exercises interleaved accessors, PBR images and seams.
        cls.repo = Path(__file__).resolve().parents[4]
        cls.fixture = cls.repo/'assets/models/bunker_switchgear/bunker_switchgear.glb'

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.source = self.work/'input.glb'
        self.source.write_bytes(self.fixture.read_bytes())

    def prepare(self, origin='bottom-center', angle=90):
        return prop.prepare(SimpleNamespace(source=str(self.source), output=str(self.work/'prepared'),
                            asset='test_prop', size=[2, 3, 1], origin=origin, rotation_y=angle,
                            front='+Z', ratio=None, gltfpack=None, error=0.025))

    def test_fit_origins_attributes_and_texture_preservation(self):
        before = self.source.read_bytes()
        for origin in ['bottom-center', 'center']:
            dest = self.work/(origin+'.glb')
            prop.fit(self.source, dest, [2, 3, 1], origin, 90)
            doc, binary, _ = prop.decode(dest); p = prop.supported(doc, binary)
            v = prop.accessor(doc, binary, p['attributes']['POSITION'])
            np.testing.assert_allclose(v.max(0)-v.min(0), [2, 3, 1], atol=1e-6)
            np.testing.assert_allclose((v.max(0)+v.min(0))/2, [0, 1.5 if origin == 'bottom-center' else 0, 0], atol=1e-6)
            normals = prop.accessor(doc, binary, p['attributes']['NORMAL'])
            tangents = prop.accessor(doc, binary, p['attributes']['TANGENT'])[:, :3]
            np.testing.assert_allclose(np.linalg.norm(normals, axis=1), 1, atol=1e-6)
            np.testing.assert_allclose(np.linalg.norm(tangents, axis=1), 1, atol=1e-6)
            np.testing.assert_allclose(np.sum(normals*tangents, axis=1), 0, atol=1e-6)
            original_doc, original_bin, _ = prop.decode(self.source)
            self.assertEqual(prop.image_bytes(doc, binary), prop.image_bytes(original_doc, original_bin))
        self.assertEqual(before, self.source.read_bytes())

    def test_rotation_before_fit_and_invalid_input(self):
        doc, binary, _ = prop.decode(self.source)
        pos = prop.accessor(doc, binary, doc['meshes'][0]['primitives'][0]['attributes']['POSITION']).copy()
        meta = prop.fit(self.source, self.work/'rotated.glb', [2, 3, 1], 'center', 90)
        np.testing.assert_allclose(meta['fit_scale_xyz'], np.array([2, 3, 1])/np.ptp(pos, axis=0)[[2, 1, 0]], rtol=1e-6)
        for size in [[0, 1, 1], [1, float('nan'), 1]]:
            with self.assertRaises(ValueError): prop.fit(self.source, self.work/'bad.glb', size, 'center', 0)
        doc['nodes'][0]['translation'] = [0, 1, 0]
        with self.assertRaises(ValueError): prop.supported(doc, binary)

    def test_publish_preserves_wrapper_and_exports_compact_source(self):
        params = self.prepare()
        repo = self.work/'repo'; repo.mkdir()
        scene = repo/'prop.tscn'
        original = ('[gd_scene load_steps=2 format=3 uid="uid://abc"]\r\n\r\n'
                    '[node name="prop" type="StaticBody3D"]\r\n\r\n'
                    '[node name="Model" type="Node3D" parent="Visuals"]\r\nposition = Vector3(2, 3, 4)\r\n\r\n'
                    '[node name="Blockout" type="MeshInstance3D" parent="Visuals/Model"]\r\n'
                    'visible = true\r\nmetadata/list = [1, 2]\r\n\r\n'
                    '[node name="Collision" type="CollisionShape3D" parent="."]\r\n'
                    'position = Vector3(0, 1, 0)\r\nshape = SubResource("collision")\r\n').encode()
        snapshot = self.work/'before.tscn'; snapshot.write_bytes(original)
        scene.write_bytes(original+b'# concurrent edit\r\n')
        args = SimpleNamespace(repo=str(repo), scene='prop.tscn', expected_scene=str(snapshot),
                               prepared=str(self.work/'prepared'), hide=['Blockout'])
        with self.assertRaises(ValueError): prop.publish(args)
        self.assertFalse((repo/'assets').exists())
        scene.write_bytes(original)
        prop.publish(args)
        patched = scene.read_bytes()
        self.assertIn(b'load_steps=3', patched)
        self.assertIn(b'[node name="Model" type="Node3D" parent="Visuals"]\r\nposition = Vector3(2, 3, 4)\r\n\r\n[node name="Asset"', patched)
        self.assertEqual(patched.count(b'visible = '), 1)
        self.assertIn(b'visible = false\r\nmetadata/list = [1, 2]', patched)
        self.assertTrue(patched.endswith(original[original.index(b'[node name="Collision"'):]))
        self.assertNotIn(b'\n', patched.replace(b'\r\n', b''))
        editable = repo/'art_source/test_prop/editable'
        doc, binary, _ = prop.decode(self.work/'prepared/final.glb')
        ext = json.loads((editable/'test_prop.gltf').read_text()); compact = (editable/'test_prop.bin').read_bytes()
        self.assertLess(len(compact), len(binary))
        for i in range(len(doc['accessors'])):
            np.testing.assert_array_equal(prop.accessor(doc, binary, i), prop.accessor(ext, compact, i))
        for i, expected in enumerate(params['texture_sha256']):
            self.assertEqual(prop.sha((editable/f'test_prop_texture_{i}.png').read_bytes()), expected)
        self.assertEqual(prop.sha((repo/'assets/models/test_prop/test_prop.glb').read_bytes()), params['final_sha256'])
        with self.assertRaises(ValueError): prop.publish(args)

    def test_existing_typed_asset_rejected(self):
        before = ('[gd_scene format=3]\n\n[node name="Model" type="Node3D" parent="Visuals"]\n\n'
                  '[node name="Asset" type="Node3D" parent="Visuals/Model"]\n').encode()
        with self.assertRaises(ValueError): prop.wrapper_bytes(before, 'test_prop', ['Blockout'])


if __name__ == '__main__':
    unittest.main()
