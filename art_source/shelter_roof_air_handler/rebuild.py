"""Rebuild a reviewed roof air handler visual in a NEW directory; never overwrite the source."""
import argparse, json, subprocess
from pathlib import Path
from refine import fit, sha

HERE=Path(__file__).resolve().parent
RAW_SHA='c17d1ee5f39292895df68104c6583930a05877dd1be3f26dac565bef0cba4ee2'
FINAL_SHA='d2e8541aa89cd074dd743b55e261db1ec9ae76f30b8ab7d64a5e7645a19e7118'

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gltfpack',required=True)
    parser.add_argument('--output',required=True)
    args=parser.parse_args()
    out=Path(args.output).resolve()
    if out.exists():raise ValueError('Output exists; use a new directory to preserve previous work')
    source=HERE/'raw.glb'
    assert sha(source.read_bytes())==RAW_SHA,'Raw source differs from reviewed source'
    version=subprocess.run([args.gltfpack,'-v'],capture_output=True,text=True,check=True)
    assert (version.stdout+version.stderr).strip()=='gltfpack 1.3','Recorded rebuild requires gltfpack 1.3'
    out.mkdir(parents=True)
    fit(source,out/'source.glb',-90)
    subprocess.run([args.gltfpack,'-i',str(out/'source.glb'),'-o',str(out/'reduced.glb'),
                    '-si','0.12','-se','0.02','-sp','-sv','-noq','-kn','-km',
                    '-r',str(out/'reduction.json')],check=True)
    meta=fit(out/'reduced.glb',out/'shelter_roof_air_handler.glb',0,out/'editable')
    assert meta['output_sha256']==FINAL_SHA,'Rebuild output differs; inspect it before replacement'
    assert sha(source.read_bytes())==RAW_SHA
    print(json.dumps({'state':'PASS','output':str(out/'shelter_roof_air_handler.glb'),'sha256':FINAL_SHA}))

if __name__=='__main__':main()
