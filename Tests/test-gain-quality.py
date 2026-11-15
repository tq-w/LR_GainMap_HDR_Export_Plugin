from pathlib import Path
import importlib.util,subprocess,json,hashlib
work=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('payload',work/'heic-payload.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
runner=work.parent/'export_heic.lrdevplugin/HEICExport';core=work.parent/'export_heic.lrdevplugin/toGainMapHDR'
root=work.parent/'build/tests/gain-quality-tests';root.mkdir(exist_ok=True)
source=work.parent/'build/tests/textured-hdr.tif'
sourceHash=hashlib.sha256(source.read_bytes()).hexdigest()
results=[]
def encode(name,source=source,depth=10,scale=2,q=None,mainq=.7,mode='iso'):
 folder=root/name;folder.mkdir(exist_ok=True)
 args=[str(runner),str(source),str(folder),'--mode',mode,'--depth',str(depth),'--scale',str(scale),'--quality',str(mainq),'--collision','overwrite']
 if q is not None:args+=['--gain-quality',str(q)]
 r=subprocess.run(args,capture_output=True,text=True)
 assert r.returncode==0,(args,r.stdout,r.stderr)
 path=folder/(source.stem+'.heic')
 assert not list(folder.glob('.heic-export-*'))
 return path
baseline=encode('default')
paths=[]
for q in [.2,.5,.8,1]:
 p=encode(f'q{q}',q=q);paths.append(p);results.append(module.inspect(p))
assert len({r['mainHash'] for r in results})==1,'gain quality changed main codestream'
assert len({r['gainHash'] for r in results})==4,'quality has no real coding effect'
assert [r['gain'] for r in results]==sorted(r['gain'] for r in results),'quality/size order reversed'
mainChanged=module.inspect(encode('mainq03',q=.8,mainq=.3))
assert mainChanged['mainHash']!=results[2]['mainHash']
assert mainChanged['gainHash']==results[2]['gainHash'],'main quality changed gain coding'
subprocess.run(['swift',str(work/'verify-gain-quality.swift'),str(baseline),*map(str,paths)],check=True)
print('PASS synthetic texture: gain quality changes payload; main payload unchanged; main quality independently changes only main',flush=True)
# Check scaled/unscaled, odd dimensions, both main depths, and extreme values.
for depth in [8,10]:
 for scale in [1,1.5,2]:
  for q in [0,1]:
   p=encode(f'odd-{depth}-{scale}-{q}',source=work.parent/'build/tests/odd-hdr.tif',depth=depth,scale=scale,q=q)
   subprocess.run(['swift',str(work/'inspect-hdr-format.swift'),str(p)],check=True,stdout=subprocess.DEVNULL)
subprocess.run(['swift',str(work/'verify-gain-fixtures.swift'),str(root)],check=True)
print('PASS 8/10-bit, full size and fractional scales 1/1.5/2, odd dimensions, quality 0 and 1',flush=True)
# All disabled modes reject explicitly supplied gain quality before touching output.
for mode in ['apple','pq','hlg','sips']:
 r=subprocess.run([str(runner),str(source),str(root),'--mode',mode,'--gain-quality','.8'],capture_output=True,text=True)
 assert r.returncode==1 and '仅适用' in r.stderr
for q in ['nan','inf','-0.1','1.1','no']:
 r=subprocess.run([str(runner),str(source),str(root),'--gain-quality',q],capture_output=True,text=True)
 assert r.returncode==1
 r=subprocess.run([str(core),str(source),str(root),'-Q',q],capture_output=True,text=True)
 assert r.returncode==1
assert hashlib.sha256(source.read_bytes()).hexdigest()==sourceHash
(root/'payload-results.json').write_text(json.dumps(results,indent=2))
print('PASS invalid quality and non-ISO modes rejected; input unchanged',flush=True)
print(json.dumps([dict(quality=q,gain=r['gain'],total=r['total']) for q,r in zip([20,50,80,100],results)],indent=2))
