"""Fit an original or reduced gas-can GLB; export editable glTF without altering input.

Python + numpy. All dimensions are baked once into vertices. The gameplay scene
owns the placement offset; this source always has a centered metric bounding box.
"""
import argparse
import copy
import hashlib
import json
import math
import struct
from pathlib import Path

import numpy as np

TARGET = np.array([0.39759523, 0.84584963, 0.82353514])

def sha(data):
    return hashlib.sha256(data).hexdigest()

def decode(path):
    data = Path(path).read_bytes()
    assert struct.unpack_from('<4sII', data) == (b'glTF', 2, len(data))
    n, kind = struct.unpack_from('<II', data, 12)
    assert kind == 0x4e4f534a
    doc = json.loads(data[20:20+n])
    bn, kind = struct.unpack_from('<II', data, 20+n)
    assert kind == 0x004e4942
    return doc, bytearray(data[28+n:28+n+bn]), data

def accessor(doc, binary, index):
    acc = doc['accessors'][index]
    view = doc['bufferViews'][acc['bufferView']]
    width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[acc['type']]
    dtype = {5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[acc['componentType']]
    offset = view.get('byteOffset',0)+acc.get('byteOffset',0)
    stride = view.get('byteStride',np.dtype(dtype).itemsize*width)
    assert not acc.get('sparse') and view.get('buffer',0)==0
    return np.ndarray((acc['count'],width),dtype=dtype,buffer=binary,
                      offset=offset,strides=(stride,np.dtype(dtype).itemsize))

def normalize(rows):
    lengths = np.linalg.norm(rows,axis=1,keepdims=True)
    assert np.min(lengths)>1e-8
    return rows/lengths

def encode(doc,binary):
    doc['buffers'][0]['byteLength']=len(binary)
    js=json.dumps(doc,separators=(',',':')).encode()
    js+=b' '*(-len(js)%4)
    buf=bytes(binary)+b'\0'*(-len(binary)%4)
    return (struct.pack('<4sII',b'glTF',2,28+len(js)+len(buf))
            +struct.pack('<II',len(js),0x4e4f534a)+js
            +struct.pack('<II',len(buf),0x004e4942)+buf)

def fit(source,dest,rotation_y,editable=None):
    source=Path(source); dest=Path(dest)
    doc,binary,original=decode(source)
    assert len(doc['nodes'])==1 and len(doc['meshes'])==1
    assert not any(k in doc['nodes'][0] for k in ['matrix','translation','rotation','scale'])
    assert not doc.get('animations') and not doc.get('skins')
    primitive=doc['meshes'][0]['primitives'][0]
    assert len(doc['meshes'][0]['primitives'])==1 and primitive.get('mode',4)==4
    theta=math.radians(rotation_y)
    rot=np.array([[math.cos(theta),0,math.sin(theta)],[0,1,0],[-math.sin(theta),0,math.cos(theta)]])
    positions=accessor(doc,binary,primitive['attributes']['POSITION'])
    pts=positions.astype(np.float64)@rot.T
    low,high=pts.min(axis=0),pts.max(axis=0)
    size=high-low; pivot=(low+high)/2
    assert np.all(size>1e-6)
    scale=TARGET/size
    positions[:]=(pts-pivot)*scale
    acc=doc['accessors'][primitive['attributes']['POSITION']]
    acc['min']=positions.min(axis=0).tolist(); acc['max']=positions.max(axis=0).tolist()
    normals=accessor(doc,binary,primitive['attributes']['NORMAL'])
    nr=normalize((normals.astype(np.float64)@rot.T)/scale)
    normals[:]=nr
    tangent_repairs=0
    if 'TANGENT' in primitive['attributes']:
        tangents=accessor(doc,binary,primitive['attributes']['TANGENT'])
        tr=(tangents[:,:3].astype(np.float64)@rot.T)*scale
        tr-=nr*np.sum(tr*nr,axis=1,keepdims=True)
        bad=np.linalg.norm(tr,axis=1)<1e-8
        tangent_repairs=int(bad.sum())
        if tangent_repairs:
            ids=accessor(doc,binary,primitive['indices']).reshape(-1,3)
            uv=accessor(doc,binary,primitive['attributes']['TEXCOORD_0']).astype(np.float64)
            pos=positions.astype(np.float64)
            edges1=pos[ids[:,1]]-pos[ids[:,0]];edges2=pos[ids[:,2]]-pos[ids[:,0]]
            uv1=uv[ids[:,1]]-uv[ids[:,0]];uv2=uv[ids[:,2]]-uv[ids[:,0]]
            determinant=uv1[:,0]*uv2[:,1]-uv1[:,1]*uv2[:,0]
            good=np.abs(determinant)>1e-12
            tri_t=np.zeros_like(edges1)
            tri_t[good]=(edges1[good]*uv2[good,1,None]-edges2[good]*uv1[good,1,None])/determinant[good,None]
            tri_t*=np.linalg.norm(np.cross(edges1,edges2),axis=1,keepdims=True)
            sums=np.zeros_like(tr)
            for col in range(3): np.add.at(sums,ids[:,col],tri_t)
            sums-=nr*np.sum(sums*nr,axis=1,keepdims=True)
            for index in np.flatnonzero(bad):
                t=sums[index]
                if np.linalg.norm(t)<1e-8:
                    axis=np.eye(3)[np.argmin(np.abs(nr[index]))]
                    t=np.cross(axis,nr[index])
                tr[index]=t
        tangents[:,:3]=normalize(tr)
    doc['nodes'][0]['name']='GasCan'
    doc['meshes'][0]['name']='GasCanMesh'
    doc['materials'][0]['name']='WornIndustrialSteel'
    doc['asset']['generator']='TRELLIS.2; gas_can/refine.py metric center fit'
    dest.parent.mkdir(parents=True,exist_ok=True)
    output=encode(doc,binary); dest.write_bytes(output)
    image_hashes=[]
    for im in doc['images']:
        view=doc['bufferViews'][im['bufferView']]
        start=view.get('byteOffset',0)
        image_hashes.append(sha(binary[start:start+view['byteLength']]))
    if editable:
        folder=Path(editable); folder.mkdir(parents=True,exist_ok=True)
        ext=copy.deepcopy(doc)
        ext['buffers'][0]['uri']='gas_can.bin'
        (folder/'gas_can.bin').write_bytes(binary)
        for index,im in enumerate(ext['images']):
            view=doc['bufferViews'][im.pop('bufferView')]
            start=view.get('byteOffset',0)
            filename=f'gas_can_texture_{index}.png'
            im['uri']=filename
            (folder/filename).write_bytes(binary[start:start+view['byteLength']])
        (folder/'gas_can.gltf').write_text(json.dumps(ext,indent=2)+'\n',encoding='utf-8')
    ids=accessor(doc,binary,primitive['indices'])
    meta={'source_sha256':sha(original),'output_sha256':sha(output),
          'rotation_y_degrees':rotation_y,'source_rotated_size_m':size.tolist(),
          'fit_scale_xyz':scale.tolist(),'target_size_m':TARGET.tolist(),
          'actual_size_m':(positions.max(axis=0)-positions.min(axis=0)).tolist(),
          'actual_center_m':((positions.max(axis=0)+positions.min(axis=0))/2).tolist(),
          'origin':'bounding box center','up':'+Y','broad_front':'+X','thickness':'X','handle_length':'Z',
          'scene_offset_baked':False,'triangles':len(ids)//3,'vertices':len(positions),
          'texture_sha256':image_hashes,'topology_changed_in_fit':False,
          'normal_handling':'inverse transpose; tangent orthogonalization',
          'zero_tangents_repaired':tangent_repairs,
          'finite_geometry':bool(np.isfinite(positions).all())}
    dest.with_suffix('.fit.json').write_text(json.dumps(meta,indent=2)+'\n',encoding='utf-8')
    assert source.read_bytes()==original
    return meta

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',required=True);p.add_argument('--output',required=True)
    p.add_argument('--rotation-y',type=float,default=0);p.add_argument('--editable')
    a=p.parse_args()
    print(json.dumps(fit(a.source,a.output,a.rotation_y,a.editable)))
