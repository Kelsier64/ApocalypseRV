"""Bed-only orientation/shape diagnostics; not a general production validator.

Post fits use the open gap between mattresses, avoiding cloth and rail vertices.
Angles are approximate centerline diagnostics. Meshes are never modified.
"""
import json
import sys
from pathlib import Path
import numpy as np

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[2]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / 'scripts'))
from prepare_request_model import load_glb, accessor


def vertices(path):
    doc, blob = load_glb(path)
    primitive = doc['meshes'][0]['primitives'][0]
    points = accessor(doc, blob, primitive['attributes']['POSITION']).astype(float)
    faces = accessor(doc, blob, primitive['indices']).reshape(-1, 3).astype(int)
    triangles = points[faces]
    areas = np.linalg.norm(np.cross(triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0]), axis=1)
    # Area sampling avoids unequal triangulation / duplicated UV-seam vertices
    # biasing a post's centerline toward whichever side has more vertices.
    rng = np.random.default_rng(7)
    triangles = triangles[rng.choice(len(faces), 200000, p=areas / areas.sum())]
    u = np.sqrt(rng.random((len(triangles), 1)))
    v = rng.random((len(triangles), 1))
    samples = triangles[:, 0] * (1 - u) + triangles[:, 1] * (u * (1 - v)) + triangles[:, 2] * (u * v)
    return points, samples


def yaw_frame(points):
    best = None
    for degrees in np.arange(-90, 90, .1):
        angle = np.deg2rad(degrees)
        rotation = np.array([[np.cos(angle), 0, -np.sin(angle)], [0, 1, 0], [np.sin(angle), 0, np.cos(angle)]])
        extent = np.ptp(points @ rotation.T, axis=0)
        if extent[0] < extent[2]:
            continue
        score = extent[0] * extent[2]
        if best is None or score < best[0]:
            best = (score, degrees, rotation)
    return best[1:]


def measure(folder):
    path = folder / 'raw.glb'
    raw, samples = vertices(path)
    if folder.name == 'original_rigid':
        rotation = np.array(json.loads((BASE.parent / 'bunker_bunk_bed_preparation.json').read_text())['rotation_rows'])
        method = 'Previous OBB rotation only; no scaling (compare to original_fitted)'
    elif folder.name == 'original_fitted':
        rotation = np.eye(3)
        method = 'Existing candidate, previous nonuniform fit already baked'
    else:
        yaw, rotation = yaw_frame(raw)
        method = f'Yaw-only minimum XZ footprint ({yaw:.1f} degrees); preserves source up'
    (folder / 'pose.json').write_text(json.dumps({'rotation_rows': rotation.tolist(), 'method': method}, indent=2) + '\n')
    points = raw @ rotation.T
    lo, hi = points.min(0), points.max(0)
    size = hi - lo
    points = samples @ rotation.T
    p = (points - lo) / size
    gap = points[(p[:, 1] > .40) & (p[:, 1] < .65)]
    gap_lo = gap.min(0)
    gap_size = np.ptp(gap, axis=0)
    gap_position = (points - gap_lo) / np.maximum(gap_size, 1e-12)
    post_fits = []
    # The chosen reference has an open central region. ROI includes only corner
    # posts in that region; fail explicitly rather than guessing absent corners.
    for left in [True, False]:
        for front in [True, False]:
            selection = (p[:, 1] > .40) & (p[:, 1] < .65)
            selection &= (gap_position[:, 0] < .12) if left else (gap_position[:, 0] > .88)
            selection &= (gap_position[:, 2] < .15) if front else (gap_position[:, 2] > .85)
            pts = points[selection]
            centers = []
            for a, b in zip(np.linspace(.40, .65, 9)[:-1], np.linspace(.40, .65, 9)[1:]):
                band = pts[(pts[:, 1] >= lo[1] + a * size[1]) & (pts[:, 1] < lo[1] + b * size[1])]
                if len(band) >= 4:
                    centers.append(np.median(band, axis=0))
            entry = {'corner': ('left' if left else 'right') + '_' + ('near' if front else 'far'), 'surface_samples_in_roi': len(pts), 'bands': len(centers)}
            if len(centers) >= 5:
                c = np.array(centers)
                slopes = np.linalg.lstsq(np.column_stack([c[:, 1], np.ones(len(c))]), c[:, [0, 2]], rcond=None)[0][0]
                direction = np.array([slopes[0], 1, slopes[1]])
                direction /= np.linalg.norm(direction)
                entry['axis'] = direction.tolist()
                entry['tilt_degrees'] = float(np.rad2deg(np.arccos(direction[1])))
            post_fits.append(entry)
    axes = np.array([x['axis'] for x in post_fits if 'axis' in x])
    spread = None
    mean_tilt = None
    if len(axes) == 4:
        mean = axes.mean(0)
        mean /= np.linalg.norm(mean)
        mean_tilt = float(np.rad2deg(np.arccos(np.clip(mean[1], -1, 1))))
        spread = float(np.rad2deg(np.arccos(np.clip(axes @ mean, -1, 1))).max())
    result = {'case': folder.name, 'pose_method': method, 'extent': size.tolist(), 'height_per_length': float(size[1] / size[0]), 'depth_per_length': float(size[2] / size[0]), 'corner_gap_post_fits': post_fits, 'mean_post_tilt_from_up_degrees': mean_tilt, 'max_post_deviation_from_mean_degrees': spread, 'sampling': '200000 area-weighted surface points, fixed diagnostic RNG 7', 'limitations': 'Approximate median fits in 40-65% height corner regions only; not a full-post or rail-straightness guarantee. ROI may overlap ladder or rails. No geometry edits.'}
    (folder / 'measurements.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: result[k] for k in ['case', 'height_per_length', 'depth_per_length', 'mean_post_tilt_from_up_degrees', 'max_post_deviation_from_mean_degrees']}))


if __name__ == '__main__':
    for name in sys.argv[1:]:
        measure(BASE / name)
