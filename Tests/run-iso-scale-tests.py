from pathlib import Path
import subprocess

work = Path(__file__).resolve().parent
root = work.parent / 'build/tests/iso-scale-tests'
exe = work.parent / 'export_heic.lrdevplugin/toGainMapHDR'
source = work.parent / 'build/tests/synthetic-hdr.tif'
for depth in [8, 10]:
    for scale in [1.0, 1.5, 2.0]:
        out = root / f'iso-{depth}-{scale}'
        out.mkdir(parents=True, exist_ok=True)
        result = subprocess.run([str(exe), str(source), str(out), '-d', str(depth), '-H', str(scale)],
                                text=True, capture_output=True)
        assert result.returncode == 0, (depth, scale, result.stdout, result.stderr)
        assert 'SDR image' not in result.stdout
for mode, flags in [('apple', ['-g', '-d', '8', '-H', '2']), ('pq', ['-p', '-d', '10'])]:
    out = root / mode
    out.mkdir(exist_ok=True)
    r = subprocess.run([str(exe), str(source), str(out), *flags], capture_output=True, text=True)
    assert r.returncode == 0, (mode, r.stdout, r.stderr)
print('Encoded six ISO cases plus Apple and PQ regression samples', flush=True)
for args in [
    ['verify-iso-scale.swift', str(root)],
    ['verify-pq.swift', str(root / 'pq/synthetic-hdr.heic')],
    ['inspect-gainmap.swift', str(root / 'apple/synthetic-hdr.heic')],
]:
    subprocess.run(['swift', str(work / args[0]), *args[1:]], check=True)
