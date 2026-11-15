from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import hashlib
import subprocess
import time
import tempfile

work = Path(__file__).resolve().parent
runner = work.parent / 'export_heic.lrdevplugin/HEICExport'
source = work.parent / 'build/tests/synthetic-hdr.tif'
root = Path(tempfile.mkdtemp(prefix='export-safety-', dir=source.parent))
subprocess.run(['swift', str(work/'create-safety-fixtures.swift'), str(root), str(source)], check=True)

def run(folder, mode='iso', collision='rename', input=source):
    return subprocess.run([str(runner), str(input), str(folder), '--mode', mode,
        '--depth','10','--scale','2','--collision',collision], text=True, capture_output=True)

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

folder = root/'policies'; folder.mkdir()
assert run(folder).returncode == 0
first = folder/'synthetic-hdr.heic'; original = digest(first)
assert run(folder, 'hlg').returncode == 0
assert digest(first) == original and (folder/'synthetic-hdr (2).heic').is_file()
r = run(folder, 'pq', 'skip')
assert r.returncode == 10 and digest(first) == original and len(list(folder.iterdir())) == 2
assert run(folder, 'pq', 'overwrite').returncode == 0 and digest(first) != original
for mode, path, transfer in [('hlg',folder/'synthetic-hdr (2).heic','HLG'),('pq',first,'PQ')]:
    subprocess.run(['swift', str(work/'verify-direct-hdr.swift'), str(path), mode], check=True)
print('PASS: rename / skip / overwrite; valid 10-bit PQ and HLG, no gain maps', flush=True)

for input in [root/'sdr.tif', root/'sdr.jpg']:
    target = folder/(input.stem+'.heic'); target.write_bytes(b'keep-original')
    result = run(folder, 'hlg', 'overwrite', input)
    assert result.returncode == 1 and target.read_bytes() == b'keep-original'
    assert input.is_file() and not list(folder.glob('.heic-export-*'))
print('PASS: invalid intermediate formats rejected; existing HEIC and inputs preserved', flush=True)

parallel = root/'parallel'; parallel.mkdir()
with ThreadPoolExecutor(max_workers=4) as pool:
    results = list(pool.map(lambda _: run(parallel), range(4)))
assert all(r.returncode == 0 for r in results), results
assert len(list(parallel.glob('*.heic'))) == 4 and not list(parallel.glob('.heic-export-*'))
print('PASS: four concurrent exports produce four distinct HEIC files', flush=True)

race = root/'race'; race.mkdir()
process = subprocess.Popen([str(runner),str(root/'large-hdr.tif'),str(race),
    '--mode','iso','--scale','2','--collision','skip'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
while process.poll() is None and not list(race.glob('.heic-export-*')):
    time.sleep(0.002)
assert list(race.glob('.heic-export-*')), 'race test did not reach encoding phase'
target = race/'large-hdr.heic'; target.write_bytes(b'created-during-encoding')
stdout,stderr = process.communicate()
assert process.returncode == 10, (process.returncode,stdout,stderr)
assert target.read_bytes() == b'created-during-encoding' and not list(race.glob('.heic-export-*'))
print('PASS: a destination created during encoding is skipped without overwriting', flush=True)

sips = root/'sips'; sips.mkdir()
assert run(sips,'sips','rename',root/'sdr.tif').returncode == 0
assert run(sips,'sips','rename',root/'sdr.tif').returncode == 0
assert (sips/'sdr.heic').is_file() and (sips/'sdr (2).heic').is_file()
print('PASS: SIPS uses the same final HEIC collision protection', flush=True)
print('Verified test files:',root)
