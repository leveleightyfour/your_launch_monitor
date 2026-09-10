"""Validate the GLB container, embedded resources, and mesh buffers."""
from pathlib import Path
import json, struct
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
p=ROOT.parents[1]/'assets/models/srixon_zxi7_7_head.glb'
data=p.read_bytes(); magic,version,length=struct.unpack_from('<4sII',data)
assert magic==b'glTF' and version==2 and length==len(data)
n,typ=struct.unpack_from('<I4s',data,12);assert typ==b'JSON'
g=json.loads(data[20:20+n]);offset=20+n
bn,bt=struct.unpack_from('<I4s',data,offset);assert bt==b'BIN\x00'
bin=data[offset+8:offset+8+bn]
assert all('uri' not in b for b in g['buffers'])
assert all('bufferView' in im and 'uri' not in im for im in g['images'])
assert not g.get('cameras') and 'KHR_lights_punctual' not in g.get('extensions',{})
for bv in g['bufferViews']:
    assert bv.get('byteOffset',0)+bv['byteLength']<=len(bin)
for im in g['images']:
    bv=g['bufferViews'][im['bufferView']];o=bv.get('byteOffset',0)
    assert bin[o:o+8]==b'\x89PNG\r\n\x1a\n'
types={5126:np.dtype('<f4'),5125:np.dtype('<u4'),5123:np.dtype('<u2'),5121:np.dtype('u1')}
count={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
def accessor(i):
    a=g['accessors'][i];bv=g['bufferViews'][a['bufferView']];dt=types[a['componentType']];nc=count[a['type']]
    ar=np.ndarray((a['count'],nc),dtype=dt,buffer=bin,offset=bv.get('byteOffset',0)+a.get('byteOffset',0),strides=(bv.get('byteStride',dt.itemsize*nc),dt.itemsize))
    assert np.isfinite(ar).all()
    return ar
triangles=0;degenerate=0;primitives=0;positions=[]
for mesh in g['meshes']:
    for prim in mesh['primitives']:
        primitives+=1
        assert prim.get('mode',4)==4
        pos=accessor(prim['attributes']['POSITION']);positions.append(pos)
        idx=accessor(prim['indices']).flatten()
        assert len(idx)%3==0 and idx.max()<len(pos)
        normal=accessor(prim['attributes']['NORMAL'])
        assert np.allclose(np.linalg.norm(normal,axis=1),1,atol=.005)
        if 'TEXCOORD_0' in prim['attributes']:accessor(prim['attributes']['TEXCOORD_0'])
        tr=idx.reshape(-1,3);triangles+=len(tr)
        areas=np.linalg.norm(np.cross(pos[tr[:,1]]-pos[tr[:,0]],pos[tr[:,2]]-pos[tr[:,0]]),axis=1)
        degenerate+=int((areas<1e-13).sum())
report={'container':'PASS','all_resources_embedded':True,'finite_buffers_and_unit_normals':'PASS','indices_in_range':'PASS','embedded_PNG_images':len(g['images']),'meshes':len(g['meshes']),'primitives':primitives,'triangles':triangles,'degenerate_triangles':degenerate,'bytes':len(data),'extensions_used':g.get('extensionsUsed',[]),'external_dependencies':0}
(ROOT/'validation.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
assert degenerate==0, f'{degenerate} degenerate triangles need cleanup'
