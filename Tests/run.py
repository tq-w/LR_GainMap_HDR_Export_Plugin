from pathlib import Path
import shutil
import subprocess
import sys

here = Path(__file__).resolve().parent
repo = here.parent
root = repo / 'build/tests'
root.mkdir(parents=True, exist_ok=True)
for binary in ['swift', 'lua', 'luac', 'heif-info']:
    if not shutil.which(binary):
        sys.exit(f'Missing test dependency: {binary}. See README.md.')

subprocess.run(['luac', '-p', str(repo/'export_heic.lrdevplugin/ExportServiceProvider.lua')], check=True)
subprocess.run(['lua', str(here/'test-export-safety.lua'), str(repo/'export_heic.lrdevplugin')], check=True)
for script, target in [('create-hdr-test.swift','synthetic-hdr.tif'),
                       ('create-odd-hdr.swift','odd-hdr.tif'),
                       ('create-textured-hdr.swift','textured-hdr.tif')]:
    subprocess.run(['swift', str(here/script), str(root/target)], check=True)
for script in ['run-iso-scale-tests.py', 'test-gain-quality.py', 'test-auto-sdr.py', 'test-export-safety.py']:
    subprocess.run([sys.executable, str(here/script)], check=True)
print('All synthetic integration checks passed. Fixtures and encoded outputs:', root)
