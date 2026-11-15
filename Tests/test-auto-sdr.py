from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import hashlib
import subprocess
import tempfile

here = Path(__file__).resolve().parent
repo = here.parent
runner = repo/'export_heic.lrdevplugin/HEICExport'
hdr = repo/'build/tests/synthetic-hdr.tif'
root = Path(tempfile.mkdtemp(prefix='auto-sdr-', dir=hdr.parent))
subprocess.run(['swift', str(here/'create-safety-fixtures.swift'), str(root), str(hdr)], check=True)

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def run(source, folder, mode, depth=10, collision='rename'):
    args = [str(runner), str(source), str(folder), '--mode', mode, '--depth', str(depth),
            '--scale', '2', '--quality', '.85', '--collision', collision]
    if mode == 'iso':
        args += ['--gain-quality', '.5']  # Must be ignored for SDR without mutating the saved HDR preset.
    return subprocess.run(args, capture_output=True, text=True)

for filename in ['sdr.tif', 'sdr-srgb.tif']:
    source = root/filename
    before = digest(source)
    for mode in ['iso', 'apple', 'pq', 'hlg']:
        for depth in [8, 10]:
            folder = root/f'{source.stem}-{mode}-{depth}'; folder.mkdir()
            result = run(source, folder, mode, depth)
            assert result.returncode == 0, (mode, depth, result.stdout, result.stderr)
            assert '自动选择 SDR' in result.stdout
            output = folder/(source.stem+'.heic')
            subprocess.run(['swift', str(here/'verify-sdr.swift'), str(source), str(output), str(depth)], check=True)
            assert not list(folder.glob('.heic-export-*'))
    assert digest(source) == before
print('PASS SDR fallback for Apple/ISO/PQ/HLG, 8/10-bit, P3/sRGB; saved gain-map quality safely ignored', flush=True)

# The same preset must yield SDR and HDR correctly even when invoked concurrently.
folder = root/'mixed'; folder.mkdir()
sources = [root/'sdr.tif', hdr]
with ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(lambda source: run(source, folder, 'iso'), sources))
assert all(r.returncode == 0 for r in results), results
subprocess.run(['swift', str(here/'verify-sdr.swift'), str(sources[0]), str(folder/'sdr.heic'), '10'], check=True)
metadata = subprocess.check_output(['swift', str(here/'inspect-hdr-format.swift'), str(folder/'synthetic-hdr.heic')], text=True)
assert 'ISO gain map present:' in metadata and 'Apple gain map absent' in metadata
assert not list(folder.glob('.heic-export-*'))

# SDR takes the same atomic rename/skip/overwrite publication path as HDR.
first = folder/'sdr.heic'; before = digest(first)
assert run(sources[0], folder, 'iso').returncode == 0
assert digest(first) == before and (folder/'sdr (2).heic').is_file()
assert run(sources[0], folder, 'iso', collision='skip').returncode == 10
assert digest(first) == before
first.write_bytes(b'replace-this-test-file')
assert run(sources[0], folder, 'iso', collision='overwrite').returncode == 0
subprocess.run(['swift', str(here/'verify-sdr.swift'), str(sources[0]), str(first), '10'], check=True)
print('PASS mixed HDR/SDR exports and SDR rename/skip/overwrite protection', flush=True)
