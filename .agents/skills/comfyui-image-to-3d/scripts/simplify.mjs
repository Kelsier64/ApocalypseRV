// Fixed ComfyUI candidate reducer: one untransformed textured primitive, meshoptimizer 1.3.0.
// All variants start from the original GLB. Vertex tuples and image bytes are preserved.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';

const [sourceArg, outputArg, targetArg, moduleArg, modeArg] = process.argv.slice(2);
assert(sourceArg && outputArg && targetArg && moduleArg,
  'Usage: node simplify.mjs source.glb new-output-folder target-triangles meshopt_simplifier.js [--force-target]');
assert(modeArg === undefined || modeArg === '--force-target', 'Unknown mode');
const forceTarget = modeArg === '--force-target';
const source = path.resolve(sourceArg), output = path.resolve(outputArg);
const target = Number(targetArg);
assert(Number.isSafeInteger(target) && target > 0);
assert(!fs.existsSync(output), 'Output folder already exists: refuse overwrite');
const modulePath = path.resolve(moduleArg);
const pkg = JSON.parse(fs.readFileSync(path.join(path.dirname(modulePath), 'package.json')));
assert.equal(pkg.name, 'meshoptimizer');
assert.equal(pkg.version, '1.3.0');
const {MeshoptSimplifier: simplifier} = await import(pathToFileURL(modulePath));
await simplifier.ready;
assert(simplifier.supported);

const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const sourceBytes = fs.readFileSync(source), sourceHash = hash(sourceBytes);
function decode(bytes) {
  assert.equal(bytes.readUInt32LE(0), 0x46546c67);
  assert.equal(bytes.readUInt32LE(4), 2);
  assert.equal(bytes.readUInt32LE(8), bytes.length);
  let doc, bin;
  for (let offset = 12; offset < bytes.length;) {
    const size = bytes.readUInt32LE(offset), type = bytes.readUInt32LE(offset + 4);
    assert.equal(size % 4, 0);
    const block = bytes.subarray(offset + 8, offset + 8 + size);
    assert.equal(block.length, size);
    if (type === 0x4e4f534a) {assert(!doc); doc = JSON.parse(block.toString('utf8'));}
    else if (type === 0x004e4942) {assert(!bin); bin = block;}
    else assert.fail('Unexpected GLB chunk');
    offset += 8 + size;
  }
  assert(doc && bin);
  return [doc, bin];
}
const [doc, bin] = decode(sourceBytes);
assert.equal(doc.buffers.length, 1);
assert(doc.buffers[0].byteLength <= bin.length && bin.length - doc.buffers[0].byteLength <= 3);
assert(doc.asset?.version === '2.0');
assert(!doc.buffers[0].uri && !doc.extensionsUsed && !doc.extensionsRequired);
assert.equal(doc.nodes.length, 1);
assert.deepEqual(Object.keys(doc.nodes[0]), ['mesh']);
assert.equal(doc.nodes[0].mesh, 0);
assert.equal(doc.meshes.length, 1);
assert.equal(doc.meshes[0].primitives.length, 1);
assert(!doc.animations && !doc.skins);
const primitive = doc.meshes[0].primitives[0];
assert.equal(primitive.mode ?? 4, 4);
assert(!primitive.targets && !primitive.extensions);
const semantics = Object.keys(primitive.attributes).sort();
assert.deepEqual(semantics, ['NORMAL', 'POSITION', 'TANGENT', 'TEXCOORD_0']);
const componentCount = {SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4};
const byteSize = {5123: 2, 5125: 4, 5126: 4};
function accessor(id) {
  const a = doc.accessors[id], v = doc.bufferViews[a.bufferView];
  assert(a && v && v.buffer === 0 && !a.sparse && !a.normalized);
  assert(Number.isSafeInteger(a.count) && a.count > 0);
  const width = componentCount[a.type] * byteSize[a.componentType];
  assert(Number.isInteger(width) && width > 0);
  const start = (v.byteOffset ?? 0) + (a.byteOffset ?? 0);
  const stride = v.byteStride ?? width;
  assert(stride >= width);
  assert((a.byteOffset ?? 0) + (a.count - 1) * stride + width <= v.byteLength);
  assert(start + (a.count - 1) * stride + width <= bin.length);
  const packed = Buffer.alloc(a.count * width);
  for (let i = 0; i < a.count; i++) bin.copy(packed, i * width, start + i * stride, start + i * stride + width);
  return {a, width, packed};
}
const attrs = Object.fromEntries(semantics.map(s => [s, accessor(primitive.attributes[s])]));
const vertexCount = attrs.POSITION.a.count;
for (const [s, type] of Object.entries({POSITION:'VEC3', NORMAL:'VEC3', TEXCOORD_0:'VEC2', TANGENT:'VEC4'})) assert.equal(attrs[s].a.type, type);
assert.equal(doc.accessors.length, 5, 'Unexpected unused accessors');
assert.equal(new Set([...Object.values(primitive.attributes), primitive.indices]).size, 5);
for (const s of semantics) {
  assert.equal(attrs[s].a.componentType, 5126);
  assert.equal(attrs[s].a.count, vertexCount);
  for (let i = 0; i < attrs[s].packed.length; i += 4) assert(Number.isFinite(attrs[s].packed.readFloatLE(i)));
}
const indexData = accessor(primitive.indices);
assert.equal(indexData.a.type, 'SCALAR');
assert.equal(indexData.a.count % 3, 0);
assert([5123, 5125].includes(indexData.a.componentType));
const oldIndices = new Uint32Array(indexData.a.count);
for (let i = 0; i < oldIndices.length; i++) {
  oldIndices[i] = indexData.width === 4 ? indexData.packed.readUInt32LE(i * 4) : indexData.packed.readUInt16LE(i * 2);
  assert(oldIndices[i] < vertexCount);
}
const noOp = target >= oldIndices.length / 3;
assert(doc.images?.length > 0 && doc.materials?.length > 0);
for (const image of doc.images) {
  assert(Number.isInteger(image.bufferView) && !image.uri);
  const v = doc.bufferViews[image.bufferView];
  assert(v.buffer === 0 && v.byteLength > 0 && (v.byteOffset ?? 0) + v.byteLength <= doc.buffers[0].byteLength);
}
// Weld only byte-identical complete tuples, preserving UV and shading discontinuities.
const tupleMap = new Map(), originalForWelded = [], remap = new Uint32Array(vertexCount);
for (let i = 0; i < vertexCount; i++) {
  const key = Buffer.concat(semantics.map(s => attrs[s].packed.subarray(i * attrs[s].width, (i + 1) * attrs[s].width))).toString('base64');
  if (!tupleMap.has(key)) {tupleMap.set(key, originalForWelded.length); originalForWelded.push(i);}
  remap[i] = tupleMap.get(key);
}
const count = originalForWelded.length;
const positions = new Float32Array(count * 3), attributes = new Float32Array(count * 5);
for (let i = 0; i < count; i++) {
  const old = originalForWelded[i];
  for (let c = 0; c < 3; c++) {
    positions[i * 3 + c] = attrs.POSITION.packed.readFloatLE((old * 3 + c) * 4);
    attributes[i * 5 + c] = attrs.NORMAL.packed.readFloatLE((old * 3 + c) * 4);
  }
  for (let c = 0; c < 2; c++) attributes[i * 5 + 3 + c] = attrs.TEXCOORD_0.packed.readFloatLE((old * 2 + c) * 4);
}
const indices = Uint32Array.from(oldIndices, i => remap[i]);
const profile = {method: 'simplifyWithAttributes', relative_error_limit: forceTarget ? null : 0.002,
  normal_weights: [1, 1, 1], uv_weights: [10, 10], flags: ['LockBorder'],
  vertex_lock: null, permissive: false, update_vertices: false, prune: false,
  force_target: forceTarget, error_limit_disabled: forceTarget};
const scale = simplifier.getScale(positions, 3);
const beforePositions = hash(Buffer.from(positions.buffer));
const beforeAttributes = hash(Buffer.from(attributes.buffer));
const start = performance.now();
// Explicit user-requested research mode only: remove the error limit, retain seams/borders.
// If topology prevents the target, stop; never silently change flags or truncate triangles.
const [newIndices, error] = noOp ? [indices, 0] : simplifier.simplifyWithAttributes(
  indices, positions, 3, attributes, 5, [...profile.normal_weights, ...profile.uv_weights],
  null, target * 3, forceTarget ? Infinity : profile.relative_error_limit, profile.flags);
const attempts = [{flags: profile.flags, actual_triangles: newIndices.length / 3, reported_relative_combined_error: error}];
const elapsed = performance.now() - start;
assert.equal(hash(Buffer.from(positions.buffer)), beforePositions);
assert.equal(hash(Buffer.from(attributes.buffer)), beforeAttributes);
assert(Number.isFinite(error));
if (!forceTarget) assert(error <= profile.relative_error_limit + 1e-6);
if (forceTarget) assert(newIndices.length / 3 <= target, 'Force-mode topology still prevents target; do not silently call this target reached');
assert(newIndices.length > 0 && newIndices.length % 3 === 0 && newIndices.length <= indices.length);
// Compact only after simplification; copy all attributes from the same original tuple.
const used = noOp ? originalForWelded.map((_, i) => i) : [...new Set(newIndices)], compact = new Map(used.map((old, i) => [old, i]));
const mapping = used.map(i => originalForWelded[i]);
const outDoc = structuredClone(doc), blocks = [], views = [];
let length = 0;
function addBlock(data, targetType) {
  const pad = (4 - length % 4) % 4;
  if (pad) {blocks.push(Buffer.alloc(pad)); length += pad;}
  const view = {buffer: 0, byteOffset: length, byteLength: data.length};
  if (targetType) view.target = targetType;
  const id = views.length;
  views.push(view); blocks.push(data); length += data.length;
  return id;
}
for (const s of semantics) {
  const {width, packed, a} = attrs[s], bytes = Buffer.alloc(mapping.length * width);
  mapping.forEach((old, i) => packed.copy(bytes, i * width, old * width, (old + 1) * width));
  const outAccessor = outDoc.accessors[primitive.attributes[s]];
  outAccessor.bufferView = addBlock(bytes, 34962);
  outAccessor.byteOffset = 0;
  outAccessor.count = mapping.length;
  if (a.min || a.max) {
    const dimensions = componentCount[a.type], lo = Array(dimensions).fill(Infinity), hi = Array(dimensions).fill(-Infinity);
    for (let i = 0; i < mapping.length; i++) for (let c = 0; c < dimensions; c++) {
      const value = bytes.readFloatLE(i * width + c * 4);
      lo[c] = Math.min(lo[c], value); hi[c] = Math.max(hi[c], value);
    }
    outAccessor.min = lo; outAccessor.max = hi;
  }
}
const outIndexBytes = Buffer.alloc(newIndices.length * 4);
newIndices.forEach((old, i) => outIndexBytes.writeUInt32LE(compact.get(old), i * 4));
const outIndexAccessor = outDoc.accessors[primitive.indices];
Object.assign(outIndexAccessor, {bufferView: addBlock(outIndexBytes, 34963), byteOffset: 0, componentType: 5125, count: newIndices.length});
delete outIndexAccessor.min; delete outIndexAccessor.max;
const imageHashes = [];
for (let i = 0; i < doc.images.length; i++) {
  const image = doc.images[i];
  assert(Number.isInteger(image.bufferView) && !image.uri);
  const v = doc.bufferViews[image.bufferView];
  const bytes = bin.subarray(v.byteOffset ?? 0, (v.byteOffset ?? 0) + v.byteLength);
  assert.equal(bytes.length, v.byteLength);
  outDoc.images[i].bufferView = addBlock(bytes);
  imageHashes.push(hash(bytes));
}
outDoc.bufferViews = views;
outDoc.buffers = [{byteLength: length}];
const packedBin = Buffer.concat(blocks), binPadding = (4 - packedBin.length % 4) % 4;
let packedJson = Buffer.from(JSON.stringify(outDoc));
packedJson = Buffer.concat([packedJson, Buffer.alloc((4 - packedJson.length % 4) % 4, 0x20)]);
const packedBinary = Buffer.concat([packedBin, Buffer.alloc(binPadding)]);
const header = Buffer.alloc(12), jsonHeader = Buffer.alloc(8), binHeader = Buffer.alloc(8);
header.writeUInt32LE(0x46546c67, 0); header.writeUInt32LE(2, 4);
header.writeUInt32LE(12 + 8 + packedJson.length + 8 + packedBinary.length, 8);
jsonHeader.writeUInt32LE(packedJson.length); jsonHeader.writeUInt32LE(0x4e4f534a, 4);
binHeader.writeUInt32LE(packedBinary.length); binHeader.writeUInt32LE(0x004e4942, 4);
const resultBytes = noOp ? sourceBytes : Buffer.concat([header, jsonHeader, packedJson, binHeader, packedBinary]);
const outputMapping = noOp ? Array.from({length: vertexCount}, (_, i) => i) : mapping;
decode(resultBytes);
assert.equal(hash(fs.readFileSync(source)), sourceHash, 'Source changed');
fs.mkdirSync(output, {recursive: true});
fs.writeFileSync(path.join(output, 'raw.glb'), resultBytes, {flag: 'wx'});
fs.writeFileSync(path.join(output, 'vertex_mapping.json'), JSON.stringify(outputMapping) + '\n', {flag: 'wx'});
// Pose belongs to review, not geometry. Pass an explicit rigid pose to review.py.
const result = {
  state: newIndices.length / 3 <= target ? 'ART_REVIEW_REQUIRED' : 'TARGET_NOT_REACHED', source: path.relative(path.dirname(output), source).replaceAll('\\', '/'),
  source_sha256: sourceHash, output_sha256: hash(resultBytes), package_version: pkg.version,
  package_module_sha256: hash(fs.readFileSync(modulePath)), profile, attempts,
  requested_triangles: target, actual_triangles: newIndices.length / 3,
  target_reached: newIndices.length / 3 <= target, input_triangles: oldIndices.length / 3,
  input_vertices: vertexCount, welded_vertices: count, output_vertices: outputMapping.length, no_op: noOp,
  source_bytes: sourceBytes.length, output_bytes: resultBytes.length,
  reported_relative_combined_error: error, mesh_scale: scale,
  reported_error_times_mesh_scale: error * scale,
  error_note: 'Approximate combined geometry/weighted-attribute error, not a certified surface-distance bound.',
  elapsed_simplification_ms: elapsed, image_sha256: imageHashes,
  preservation: {vertex_positions: true, uv: true, normals: true, tangents: true, image_bytes: true,
    materials: true, samplers: true, transforms: true, axis_scaling: false, texture_rebake: false},
  acceptance: false,
};
fs.writeFileSync(path.join(output, 'simplification.json'), JSON.stringify(result, null, 2) + '\n', {flag: 'wx'});
console.log(JSON.stringify(result));

// Nonzero exit makes a missed budget a hard stop, while preserving the evidence.
if (!result.target_reached) process.exitCode = 2;
