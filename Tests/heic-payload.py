from pathlib import Path
import subprocess,re,hashlib,json,sys

def inspect(path):
 result=subprocess.run(['heif-info','-d',str(path)],capture_output=True,text=True)
 s=result.stdout
 loc=s[s.index('Box: iloc'):]
 extents={int(i):[(int(o),int(l)) for o,l in re.findall(r'(\d+),(\d+)',e)] for i,e in re.findall(r'item ID: (\d+)\n.*?extents: ([^\n]+)',loc,re.S)}
 methods={int(i):int(m) for i,m in re.findall(r'item ID: (\d+)\n[^\n]*construction method: (\d+)',loc)}
 refs={int(i):[int(t) for t in ids.split()] for i,ids in re.findall(r"reference with type 'dimg' from ID: (\d+) to IDs: ([\d ]+)",s)}
 primary=int(re.search(r'Box: pitm.*?item_ID: (\d+)',s,re.S)[1])
 tmap=[(i,t) for i,t in refs.items() if primary in t and len(t)==2]
 if tmap:
  assert len(tmap)==1,(path,tmap)
  gain=next(i for i in tmap[0][1] if i!=primary)
 else:
  aux=[int(i) for i,ids in re.findall(r"reference with type 'auxl' from ID: (\d+) to IDs: ([\d ]+)",s) if primary in [int(t) for t in ids.split()]]
  assert len(aux)==1,(path,aux)
  gain=aux[0]
 d=Path(path).read_bytes()
 def leaves(i):return sum((leaves(t) for t in refs[i]),[]) if i in refs else [i]
 def encoded(i):return b''.join(d[o:o+n] for t in leaves(i) for o,n in extents[t] if methods[t]==0)
 main=encoded(primary);gm=encoded(gain)
 return dict(file=str(path),total=len(d),main=len(main),gain=len(gm),mainHash=hashlib.sha256(main).hexdigest(),gainHash=hashlib.sha256(gm).hexdigest(),gainID=gain)
if __name__=='__main__':
 for p in sys.argv[1:]:print(json.dumps(inspect(p)))
