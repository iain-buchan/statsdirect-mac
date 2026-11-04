"""Check an ordinary app build contains its one frozen help/tutor publication."""
from pathlib import Path
import hashlib
import json
import os
import sys

ROOT = Path(__file__).resolve().parents[1]


def inventory(folder):
    result = {}
    for path in folder.rglob('*'):
        name = path.relative_to(folder).as_posix()
        if path.is_symlink():
            result[name] = {'link': os.readlink(path)}
        elif path.is_file():
            result[name] = {'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                            'mode': path.stat().st_mode & 0o777}
    return result


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: python3 Tests/test_packaged_content.py /path/to/StatsDirect.app')
    app = Path(sys.argv[1]).resolve()
    content = app / 'Contents/Resources/Content'
    assert inventory(content) == inventory(ROOT / 'Content'), 'Packaged content differs from source inputs'
    record = json.loads((app / 'Contents/Resources/content-build-input.json').read_bytes())
    help_manifest = json.loads((content / 'help-manifest.json').read_bytes())
    tutor_manifest = json.loads((content / 'learning-manifest.json').read_bytes())
    assert record['mode'] in ('latest', 'pinned', 'offline')
    assert record['revision'] == help_manifest['commit'] == tutor_manifest['commit']
    assert record['publicationManifestSHA256'] == help_manifest['publicationManifestSHA256'] == tutor_manifest['publicationManifestSHA256']
    root_manifest = (content / 'learning-source-manifest.json').read_bytes()
    assert hashlib.sha256(root_manifest).hexdigest() == record['publicationManifestSHA256']
    assert help_manifest['publicationManifestText'].encode('utf-8') == root_manifest
    bundle = (content / 'Learn/app.js').read_text()
    assert record['revision'] in bundle and record['publicationManifestSHA256'] in bundle, 'Learning bundle uses a stale publication'
    if record['mode'] != 'offline':
        assert set(record['publicationArtifacts']) == {'website', 'desktopHelp', 'tutor'}
    print('PASS: packaged help, tutor, Learning bundle and immutable build record match publication ' + record['revision'])


if __name__ == '__main__':
    main()
