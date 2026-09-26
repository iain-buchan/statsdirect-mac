#!/usr/bin/env python3
"""Bundle the pinned official Apple-silicon app-server package, never personal credentials."""
import hashlib, json, pathlib, shutil, subprocess, sys, tarfile, urllib.request

VERSION = '0.157.1'
ARCHIVE = 'codex-app-server-package-aarch64-apple-darwin.tar.gz'
SHA256 = '9a6033c9fe30260e71d784d003ad1e2de2a55c93e24a24856e8433029a3f811a'
RELEASE = f'https://github.com/openai/codex/releases/download/rust-v{VERSION}/{ARCHIVE}'
root = pathlib.Path(__file__).resolve().parent.parent
cache = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else root/'.build/codex-runtime'
cache.mkdir(parents=True, exist_ok=True)
archive = cache/'package.tar.gz'
if not archive.exists():
    download = archive.with_suffix('.download')
    subprocess.run(['curl','--fail','--location','--retry','2',RELEASE,'--output',str(download)],check=True)
    download.replace(archive)
if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
    raise SystemExit('ChatGPT runtime checksum does not match the pinned release. Remove the cached archive and retry.')
destination = pathlib.Path(sys.argv[1])/'Contents/Resources/TutorRuntime'
if destination.exists(): shutil.rmtree(destination)
destination.mkdir(parents=True)
with tarfile.open(archive) as package:
    for item in package.getmembers():
        if item.name.startswith('/') or '..' in pathlib.PurePosixPath(item.name).parts or item.issym() or item.islnk():
            raise SystemExit('Unexpected archive entry')
    package.extractall(destination)
for name in ['LICENSE','NOTICE']:
    data = urllib.request.urlopen(f'https://raw.githubusercontent.com/openai/codex/rust-v{VERSION}/{name}',timeout=30).read()
    (destination/name).write_bytes(data)
(destination/'STATSDIRECT-RUNTIME.json').write_text(json.dumps({'version':VERSION,'source':RELEASE,'sha256':SHA256,'license':'Apache-2.0'},indent=2)+'\n')
for binary in ['bin/codex-app-server','bin/codex-code-mode-host','codex-path/rg','codex-resources/zsh/bin/zsh']:
    subprocess.run(['codesign','--force','--sign','-',str(destination/binary)],check=True)
print('Bundled official ChatGPT connection runtime ' + VERSION)
