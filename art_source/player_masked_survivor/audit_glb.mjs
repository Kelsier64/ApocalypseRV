import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const sourceDir=path.dirname(fileURLToPath(import.meta.url));
const dir=path.resolve(sourceDir,process.argv[2]??'../../assets/models/player');
const failures=[];
function check(ok,msg){if(!ok)failures.push(msg);}
function readGlb(file){
 const data=fs.readFileSync(file);check(data.toString('ascii',0,4)==='glTF','GLB magic '+file);
 const len=data.readUInt32LE(12),g=JSON.parse(data.toString('utf8',20,20+len));
 const bin=data.subarray(28+len);
 function acc(i){const a=g.accessors[i],v=g.bufferViews[a.bufferView];const n={SCALAR:1,VEC2:2,VEC3:3,VEC4:4,MAT4:16}[a.type];
 const component={5120:[1,'readInt8'],5121:[1,'readUInt8'],5122:[2,'readInt16LE'],5123:[2,'readUInt16LE'],5125:[4,'readUInt32LE'],5126:[4,'readFloatLE']}[a.componentType];
 const [size,fn]=component,stride=v.byteStride??size*n,offset=(v.byteOffset??0)+(a.byteOffset??0),result=[];
 for(let j=0;j<a.count;j++){let row=[];for(let k=0;k<n;k++)row.push(bin[fn](offset+j*stride+k*size));result.push(row);}return result;}
 return {g,acc};
}
const identity=()=>[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1];
function mul(a,b){let c=Array(16).fill(0);for(let col=0;col<4;col++)for(let row=0;row<4;row++)for(let k=0;k<4;k++)c[col*4+row]+=a[k*4+row]*b[col*4+k];return c;}
function matrix(n){if(n.matrix)return n.matrix;let [x,y,z,w]=n.rotation??[0,0,0,1],s=n.scale??[1,1,1],t=n.translation??[0,0,0];
 return [(1-2*y*y-2*z*z)*s[0],(2*x*y+2*z*w)*s[0],(2*x*z-2*y*w)*s[0],0,(2*x*y-2*z*w)*s[1],(1-2*x*x-2*z*z)*s[1],(2*y*z+2*x*w)*s[1],0,(2*x*z+2*y*w)*s[2],(2*y*z-2*x*w)*s[2],(1-2*x*x-2*y*y)*s[2],0,...t,1];}
function inspect(file,full=false){const {g,acc}=readGlb(file);const worlds={};function visit(i,p){const n=g.nodes[i],m=mul(p,matrix(n));worlds[i]=m;for(const j of n.children??[])visit(j,m);}
 for(const scene of g.scenes)for(const i of scene.nodes??[])visit(i,identity());
 let triangles=0,vertices=0,maxInfluences=0,badWeights=0,missingUv=0,invalidJoints=0;const min=[Infinity,Infinity,Infinity],max=[-Infinity,-Infinity,-Infinity];
 for(let i=0;i<g.nodes.length;i++){const n=g.nodes[i];if(n.mesh===undefined)continue;const m=worlds[i];
  for(const p of g.meshes[n.mesh].primitives){triangles+=g.accessors[p.indices].count/3;const positions=acc(p.attributes.POSITION);vertices+=positions.length;
   for(const v of positions){for(let k=0;k<3;k++){const x=m[k]*v[0]+m[4+k]*v[1]+m[8+k]*v[2]+m[12+k];min[k]=Math.min(min[k],x);max[k]=Math.max(max[k],x);}}
   if(p.attributes.TEXCOORD_0===undefined)missingUv++;
   if(p.attributes.WEIGHTS_0===undefined){badWeights++;continue;}
   const weights=acc(p.attributes.WEIGHTS_0),joints=acc(p.attributes.JOINTS_0),count=g.skins[n.skin].joints.length;
   for(let k=0;k<weights.length;k++){const w=weights[k];maxInfluences=Math.max(maxInfluences,w.filter(x=>x>1e-6).length);if(Math.abs(w.reduce((a,b)=>a+b,0)-1)>1e-4)badWeights++;if(joints[k].some(j=>j<0||j>=count))invalidJoints++;}
  }
 }
 const animation=[];
 for(const a of g.animations??[]){let duration=0,rootMotion=0,loopDelta=0;
  const loop=!['jump','land'].includes(a.name);
  for(const channel of a.channels){const sampler=a.samplers[channel.sampler];const times=acc(sampler.input).flat(),values=acc(sampler.output);duration=Math.max(duration,times.at(-1)-times[0]);
   const name=g.nodes[channel.target.node].name;
   if(name==='root')for(const v of values)rootMotion=Math.max(rootMotion,...v.map((x,k)=>Math.abs(x-values[0][k])));
   if(loop)loopDelta=Math.max(loopDelta,...values[0].map((x,k)=>Math.abs(x-values.at(-1)[k])));
  } animation.push({name:a.name,duration,loop,rootMotion,loopEndpointMaxDelta:loopDelta});check(rootMotion<1e-5,'root motion '+a.name);check(!loop||loopDelta<1e-4,'loop discontinuity '+a.name);
 }
 check(badWeights===0,'weights '+file);check(missingUv===0,'UV0 '+file);check(invalidJoints===0,'skin indices '+file);check(maxInfluences<=4,'four weights '+file);
 check(g.nodes.every(n=>(n.scale??[1,1,1]).every(v=>v>0)),'negative scale '+file);
 const joints=g.skins[0].joints.map(i=>g.nodes[i].name);
 if(full){check(g.scenes.length===1,'one export scene');check(joints.length===55,'55 joints');check(triangles>=8000&&triangles<=12100,'triangle budget including documented shoulder-loop allowance');check(g.materials.length===5,'five materials');check(Math.abs(max[1]-min[1]-1.60)<.001,'1.60m height');check(Math.abs(min[1])<.001,'ground origin');
 check(animation.length===11,'11 independent clips');check(g.nodes.filter(n=>/^body_/.test(n.name)).length===10,'ten body parts');check(g.nodes.filter(n=>/^cap_/.test(n.name)).length===18,'18 caps');
 const mask=g.materials.find(m=>m.name==='mask_default');check(mask.pbrMetallicRoughness.baseColorTexture===undefined,'plain white mask');check((mask.pbrMetallicRoughness.baseColorFactor??[1,1,1,1]).every(x=>x===1),'white #ffffff');
 const suit=g.materials.find(m=>m.name==='suit_dye').pbrMetallicRoughness;check(suit.baseColorTexture!==undefined&&suit.baseColorFactor!==undefined,'separate neutral texture and tint');
 }
 return {file:path.relative(dir,file),triangles,exportedVertices:vertices,bounds:{min,max},joints,maxInfluences,badWeights,missingUv,invalidJoints,materials:g.materials.map(m=>({name:m.name,pbr:m.pbrMetallicRoughness})),embeddedImages:g.images.length,animations:animation};
}
const report={full:inspect(path.join(dir,'player_masked_survivor.glb'),true),detached:fs.readdirSync(path.join(dir,'detached')).filter(n=>n.endsWith('.glb')).map(n=>inspect(path.join(dir,'detached',n))),failures};
for(const d of report.detached){check(d.joints.includes('root'),'detached root');check(!d.joints.includes('pelvis'),'detached external ancestor');}
fs.writeFileSync(path.join(sourceDir,'work/glb_audit.json'),JSON.stringify(report,null,2));
console.log(JSON.stringify({triangles:report.full.triangles,bounds:report.full.bounds,bones:report.full.joints.length,materials:report.full.materials.length,animations:report.full.animations.length,detached:report.detached.length,failures}));
export default report;
