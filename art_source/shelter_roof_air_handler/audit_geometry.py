"""Numerical geometry and embedded-texture checks; does not replace visual review."""
import argparse, json
from collections import Counter
from pathlib import Path
import numpy as np
from refine import accessor, decode, sha, TARGET

def inspect(path):
    doc,bin,data=decode(path)
    p=doc['meshes'][0]['primitives'][0]
    attributes={key:accessor(doc,bin,index) for key,index in p['attributes'].items()}
    v=attributes['POSITION'];ids=accessor(doc,bin,p['indices']).reshape(-1,3)
    assert np.all(ids>=0) and np.max(ids)<len(v) and len(ids)>0
    assert all(np.isfinite(a).all() for a in attributes.values())
    area=np.linalg.norm(np.cross(v[ids[:,1]]-v[ids[:,0]],v[ids[:,2]]-v[ids[:,0]]),axis=1)
    _,mapping=np.unique(np.round(v/1e-6).astype(np.int64),axis=0,return_inverse=True)
    edges=Counter()
    for face in mapping[ids]:
        for a,b in [(face[0],face[1]),(face[1],face[2]),(face[2],face[0])]:
            edges[tuple(sorted((int(a),int(b))))]+=1
    images=[]
    for im in doc['images']:
        view=doc['bufferViews'][im['bufferView']];start=view.get('byteOffset',0)
        images.append(sha(bin[start:start+view['byteLength']]))
    nr=attributes['NORMAL'];tr=attributes['TANGENT']
    size=v.max(axis=0)-v.min(axis=0);center=(v.max(axis=0)+v.min(axis=0))/2
    result={'sha256':sha(data),'triangles':len(ids),'vertices':len(v),'size_m':size.tolist(),
       'center_m':center.tolist(),'max_dimension_error_m':float(np.abs(size-TARGET).max()),
       'finite_attributes':True,'zero_area_triangles':int((area<1e-12).sum()),
       'zero_tangents':int((np.linalg.norm(tr[:,:3],axis=1)<1e-8).sum()),
       'normal_unit_max_error':float(np.abs(np.linalg.norm(nr,axis=1)-1).max()),
       'tangent_unit_max_error':float(np.abs(np.linalg.norm(tr[:,:3],axis=1)-1).max()),
       'normal_tangent_dot_max':float(np.abs(np.sum(nr*tr[:,:3],axis=1)).max()),
       'duplicate_triangles_welded_1um':int(len(ids)-len(np.unique(np.sort(mapping[ids],axis=1),axis=0))),
       'boundary_edges_welded_1um':sum(n==1 for n in edges.values()),
       'nonmanifold_edges_welded_1um':sum(n>2 for n in edges.values()),
       'embedded_texture_sha256':images,'animations':len(doc.get('animations',[])),
       'skins':len(doc.get('skins',[])),'required_extensions':doc.get('extensionsRequired',[])}
    return result
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('file');p.add_argument('output');a=p.parse_args()
    result=inspect(a.file);Path(a.output).write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))
