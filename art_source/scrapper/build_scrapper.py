"""Deterministic precision meshes; metres, body +Y up, roller local +Y shaft."""
from pathlib import Path
import argparse, io, json, math, struct
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

TAU = math.tau

def texture(kind, seed=73):
    rng = np.random.default_rng(seed)
    n = 512
    noise = rng.normal(0, 1, (n, n))
    broad = np.asarray(Image.fromarray(rng.integers(0, 255, (32,32), dtype=np.uint8)).resize((n,n), Image.Resampling.BICUBIC), dtype=float)/255
    if kind in ('teal', 'orange'):
        rgb = np.array((34,69,64) if kind=='teal' else (144,79,29))
        base = rgb[None,None,:]*(.95+.07*broad[:,:,None])+noise[:,:,None]*1.2
        rough = .73 + broad*.12
    else:
        rgb = np.array((91,99,103) if kind=='steel' else (47,54,57) if kind=='dark' else (163,169,173))
        brushed = rng.normal(0, 1, (n,1))
        base = rgb[None,None,:]*(.96+.045*broad[:,:,None])+noise[:,:,None]*1.0+brushed[:,:,None]*1.4
        rough = (.49 if kind=='steel' else .64 if kind=='dark' else .32)+broad*.12
    im = Image.fromarray(np.uint8(np.clip(base,0,255)))
    d = ImageDraw.Draw(im)
    for _ in range(125 if kind in ('teal','orange') else 65):
        x,y = rng.integers(0,n,2)
        length = int(rng.integers(2,24))
        c = (83,81,69) if kind in ('teal','orange') else (128,135,137)
        d.line((int(x),int(y),int(x+length),int(y+int(rng.integers(-2,3)))),fill=c,width=1)
    packed = np.empty((n,n,3),np.uint8)
    packed[:,:,0]=255
    packed[:,:,1]=np.uint8(np.clip(rough,0,1)*255)
    packed[:,:,2]=255 if kind not in ('teal','orange') else 15
    # Subtle shallow machining marks; no baked directional lighting.
    h = noise*.002 + broad*.006
    dy,dx=np.gradient(h)
    normal=np.dstack((-dx*3,-dy*3,np.ones_like(h)))
    normal /= np.linalg.norm(normal,axis=2,keepdims=True)
    norm=Image.fromarray(np.uint8(np.clip((normal*.5+.5)*255,0,255)))
    return im,Image.fromarray(packed),norm

class Model:
    def __init__(self):
        self.surfaces={}
    def tri(self,mat,a,b,c,uv=None):
        a,b,c=[np.array(v,dtype=float) for v in (a,b,c)]
        normal=np.cross(b-a,c-a)
        if np.linalg.norm(normal)<1e-12: return
        normal/=np.linalg.norm(normal)
        points=[a,b,c]
        if uv is None:
            axis=int(np.argmax(np.abs(normal)))
            axes=[i for i in range(3) if i!=axis]
            uv=[(v[axes[0]]*2,v[axes[1]]*2) for v in points]
        duv1=np.array(uv[1])-uv[0]; duv2=np.array(uv[2])-uv[0]
        det=duv1[0]*duv2[1]-duv2[0]*duv1[1]
        if abs(det)>1e-9:
            tangent=((b-a)*duv2[1]-(c-a)*duv1[1])/det
            bitangent=((c-a)*duv1[0]-(b-a)*duv2[0])/det
            tangent-=normal*np.dot(normal,tangent)
            tangent/=np.linalg.norm(tangent)
            handed=1 if np.dot(np.cross(normal,tangent),bitangent)>0 else -1
        else:
            tangent=np.cross(normal,[1,0,0] if abs(normal[0])<.9 else [0,1,0]); tangent/=np.linalg.norm(tangent); handed=1
        s=self.surfaces.setdefault(mat,{'p':[],'n':[],'uv':[],'t':[]})
        for p,u in zip(points,uv):
            s['p'].append(p);s['n'].append(normal);s['uv'].append(u);s['t'].append([*tangent,handed])
    def face(self,mat,points):
        for i in range(1,len(points)-1):self.tri(mat,points[0],points[i],points[i+1])
    def box(self,center,size,mat,bevel=.003):
        center=np.array(center); half=np.array(size)/2; b=min(bevel,float(min(half))*.45)
        # Six planar faces, twelve chamfer faces, eight corner triangles.
        for axis in range(3):
            other=[i for i in range(3) if i!=axis]
            for sign in (-1,1):
                pts=[]
                for u,v in ((-1,-1),(1,-1),(1,1),(-1,1)):
                    p=np.zeros(3);p[axis]=half[axis]*sign;p[other[0]]=(half[other[0]]-b)*u;p[other[1]]=(half[other[1]]-b)*v;pts.append(p+center)
                if np.dot(np.cross(pts[1]-pts[0],pts[2]-pts[0]),np.eye(3)[axis]*sign)<0:pts.reverse()
                self.face(mat,pts)
        for along in range(3):
            a,c=[i for i in range(3) if i!=along]
            for sa in (-1,1):
                for sc in (-1,1):
                    pts=[]
                    for t,edge in ((-1,0),(1,0),(1,1),(-1,1)):
                        p=np.zeros(3);p[along]=t*(half[along]-b);p[a]=sa*(half[a]-(b if edge else 0));p[c]=sc*(half[c]-(0 if edge else b));pts.append(p+center)
                    out=np.zeros(3);out[a]=sa;out[c]=sc
                    if np.dot(np.cross(pts[1]-pts[0],pts[2]-pts[0]),out)<0:pts.reverse()
                    self.face(mat,pts)
        for sx in (-1,1):
            for sy in (-1,1):
                for sz in (-1,1):
                    signs=np.array([sx,sy,sz]);pts=[]
                    for axis in range(3):
                        p=(half-b)*signs;p[axis]=half[axis]*signs[axis];pts.append(p+center)
                    if np.dot(np.cross(pts[1]-pts[0],pts[2]-pts[0]),signs)<0:pts.reverse()
                    self.face(mat,pts)
    def prism(self,outline,y,thickness,mat,edge='edge',bevel=.002,hole=0,center=(0,0,0),axis=1):
        center=np.array(center)
        def pos(x,h,z):
            p=np.array([x,h,z])
            if axis==2:p=np.array([x,z,-h])
            if axis==0:p=np.array([h,-x,z])
            return p+center
        n=len(outline); rings=[]
        for h,shrink in ((y-thickness/2,bevel),(y-thickness/2+bevel,0),(y+thickness/2-bevel,0),(y+thickness/2,bevel)):
            rings.append([pos(x*(1-shrink/math.hypot(x,z)),h,z*(1-shrink/math.hypot(x,z))) for x,z in outline])
        for level in range(3):
            for i in range(n):
                j=(i+1)%n
                self.face(edge if level!=1 else mat,[rings[level][i],rings[level+1][i],rings[level+1][j],rings[level][j]])
        for top in (0,3):
            h=y+(-1 if top==0 else 1)*thickness/2
            inner=[]
            for i,(x,z) in enumerate(outline):
                angle=math.atan2(z,x)
                inner.append(pos(hole*math.cos(angle),h,hole*math.sin(angle)))
            for i in range(n):
                j=(i+1)%n
                pts=[rings[top][i],rings[top][j],inner[j],inner[i]]
                if top==3:pts.reverse()
                self.face(mat,pts)
        if hole:
            for i in range(n):
                j=(i+1)%n
                a=math.atan2(outline[i][1],outline[i][0]);c=math.atan2(outline[j][1],outline[j][0])
                self.face('dark',[pos(hole*math.cos(a),y-thickness/2,hole*math.sin(a)),pos(hole*math.cos(c),y-thickness/2,hole*math.sin(c)),pos(hole*math.cos(c),y+thickness/2,hole*math.sin(c)),pos(hole*math.cos(a),y+thickness/2,hole*math.sin(a))])
    def cylinder(self,r,y,h,mat,segments=32,center=(0,0,0),axis=1,hole=0):
        self.prism([(r*math.cos(i*TAU/segments),r*math.sin(i*TAU/segments)) for i in range(segments)],y,h,mat,bevel=min(.002,h*.15),hole=hole,center=center,axis=axis)
    def save(self,path):
        data=bytearray();views=[];access=[];images=[];textures=[];mats=[]
        def buf(raw,target=None):
            while len(data)%4:data.append(0)
            offset=len(data);data.extend(raw)
            v={'buffer':0,'byteOffset':offset,'byteLength':len(raw)}
            if target:v['target']=target
            views.append(v);return len(views)-1
        def accessor(values,dim,typ):
            ar=np.asarray(values,dtype='<f4');v=buf(ar.tobytes(),34962)
            obj={'bufferView':v,'componentType':5126,'count':len(ar),'type':typ}
            if dim==3:obj.update(min=ar.min(axis=0).tolist(),max=ar.max(axis=0).tolist())
            access.append(obj);return len(access)-1
        for kind in self.surfaces:
            indices=[]
            for im in texture(kind):
                out=io.BytesIO();im.save(out,format='PNG');v=buf(out.getvalue());images.append({'bufferView':v,'mimeType':'image/png'});textures.append({'source':len(images)-1,'sampler':0});indices.append(len(textures)-1)
            mats.append({'name':kind,'pbrMetallicRoughness':{'baseColorTexture':{'index':indices[0]},'metallicRoughnessTexture':{'index':indices[1]},'metallicFactor':1,'roughnessFactor':1},'normalTexture':{'index':indices[2],'scale':.35}})
        prim=[]
        for mi,s in enumerate(self.surfaces.values()):
            prim.append({'attributes':{'POSITION':accessor(s['p'],3,'VEC3'),'NORMAL':accessor(s['n'],3,'VEC3'),'TEXCOORD_0':accessor(s['uv'],2,'VEC2'),'TANGENT':accessor(s['t'],4,'VEC4')},'material':mi,'mode':4})
        doc={'asset':{'version':'2.0','generator':'ApocalypseRV precision scrapper authoring'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'name':path.stem,'mesh':0}],'meshes':[{'primitives':prim}],'materials':mats,'textures':textures,'images':images,'samplers':[{'magFilter':9729,'minFilter':9987,'wrapS':10497,'wrapT':10497}],'buffers':[{'byteLength':len(data)}],'bufferViews':views,'accessors':access}
        raw=json.dumps(doc,separators=(',',':')).encode();raw+=b' '*((-len(raw))%4);data+=b'\0'*((-len(data))%4)
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(raw)+len(data))+struct.pack('<II',len(raw),0x4e4f534a)+raw+struct.pack('<II',len(data),0x004e4942)+data)
        print(path.name, sum(len(s['p'])//3 for s in self.surfaces.values()), 'triangles',len(self.surfaces),'surfaces')

def body():
    m=Model()
    m.box((0,.035,0),(1.05,.07,1.05),'dark',.005)
    for sign in (-1,1):
        m.box((sign*.49,.385,0),(.07,.63,.91),'teal',.006)
        m.box((0,.385,sign*.49),(1.05,.63,.07),'teal',.006)
        # Inner liners sit on wall faces; preserve the full open feed path.
        m.box((sign*.454,.353,0),(.008,.556,.89),'steel',.002)
        m.box((0,.353,sign*.454),(.89,.556,.008),'steel',.002)
        m.box((0,.67,sign*.49),(1.05,.07,.08),'orange',.007)
        m.box((sign*.49,.67,0),(.08,.07,.90),'orange',.006)
        # Reinforced external end plates and flush bearing cartridges.
        m.box((0,.455,sign*.528),(.84,.37,.014),'dark',.004)
        for x in (-.20,.20):
            m.cylinder(.091,0,.024,'dark',32,(x,.50,sign*.541),2)
            m.cylinder(.065,0,.028,'steel',32,(x,.50,sign*.548),2)
            m.cylinder(.041,0,.031,'edge',24,(x,.50,sign*.553),2)
            m.cylinder(.025,0,.033,'dark',6,(x,.50,sign*.555),2)
            for a in (math.pi/4,3*math.pi/4,5*math.pi/4,7*math.pi/4):
                m.cylinder(.011,0,.009,'edge',6,(x+.076*math.cos(a),.50+.076*math.sin(a),sign*.558),2)
        # Low profile wall ribs and recessed maintenance panel.
        for z in (-.31,0,.31):m.box((sign*.528,.32,z),(.012,.43,.032),'teal',.003)
        m.box((sign*.531,.335,0),(.016,.27,.23),'dark',.004)
        for z in (-.102,.102):
            for y in (.225,.445):m.cylinder(.008,0,.006,'edge',6,(sign*.545,y,z),0)
        for x in (-.46,.46):
            for y in (.13,.60):m.cylinder(.012,0,.012,'edge',6,(x,y,sign*.539),2)
        # Restrained hazard stripes on top of front/back lips.
        for x in (-.39,-.31,-.23,.23,.31,.39):m.box((x,.706,sign*.49),(.035,.001,.054),'dark',.0001)
        for x in (-.43,.43):m.box((x,.081,sign*.43),(.085,.02,.085),'dark',.002)
    return m

def roller():
    m=Model()
    m.cylinder(.058,0,.965,'steel',32)
    for i in range(10):
        y=(i-4.5)*.080
        phase=i*.13
        outline=[]
        for tooth in range(7):
            # Broad root, rising hook shoulder, short cutting land, relief throat.
            for fraction,r in ((0,.163),(.20,.183),(.49,.231),(.59,.238),(.68,.187),(.84,.163)):
                a=(tooth+fraction)*TAU/7+phase
                outline.append((r*math.cos(a),r*math.sin(a)))
        m.prism(outline,y,.034,'steel','edge',.0025,.061)
        # Spacer drums between plates remain below the opposing cutting path.
        if i<9:m.cylinder(.102,y+.040,.042,'dark',24,hole=.059)
    for sign in (-1,1):
        m.cylinder(.123,sign*.423,.030,'dark',32,hole=.059)
        m.cylinder(.095,sign*.446,.015,'steel',32,hole=.059)
        m.cylinder(.076,sign*.459,.014,'edge',6,hole=.059)
    return m

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);args=p.parse_args()
    body().save(args.output/'scrapper_body.glb')
    roller().save(args.output/'scrapper_roller.glb')
