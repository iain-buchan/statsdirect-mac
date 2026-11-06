"""Record or verify the shared Learning code in the pinned statisticalhelp submodule.

The Learning page's platform-neutral code (Learn/HOST-CONTRACT.md in the package) lives in the
statisticalhelp repository's Learning/ folder and is taken here as the git submodule Learn/Upstream,
pinned by commit. This never downloads or changes that code. To move the pin: check out the wanted
commit (a learning-v* tag) in Learn/Upstream, run this with --write, review, and commit the submodule,
the manifest and the two copied files together.

--write  records the pin, the tag when the commit carries one, the host-contract number and the SHA-256
         of every file under Learning/ in Learn/upstream-manifest.json, copies index.html and learn.css
         into Content/Learn, where the app loads the page, and stages the submodule entry.
--verify (the build) checks the submodule is at the recorded commit and clean, every file's hash, the
         two copies, that the package's host-contract.json, the manifest and Sources/LearningHostContract.swift
         agree, and that Learn/package.json pins the package's dependencies.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

base = Path(__file__).resolve().parent
root = base.parent
source = base / 'Upstream'
package = source / 'Learning'
manifest_path = base / 'upstream-manifest.json'
swift_constant = root / 'Sources/LearningHostContract.swift'
copies = {'index.html': root / 'Content/Learn/index.html', 'learn.css': root / 'Content/Learn/learn.css'}
repository = 'https://github.com/iain-buchan/statisticalhelp'


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*args):
    return subprocess.check_output(['git', '-C', str(source), *args], text=True).strip()


def snapshot():
    if not (source / '.git').exists():
        raise SystemExit('The Learning submodule is missing. Run: git submodule update --init Learn/Upstream')
    if not package.is_dir():
        raise SystemExit('Learn/Upstream has no Learning/ folder at this commit.')
    revision = git('rev-parse', 'HEAD')
    if git('status', '--porcelain', '--untracked-files=no', '--', 'Learning'):
        raise SystemExit('The Learning submodule has local changes under Learning/. Restore or commit them first.')
    strays = [line[3:] for line in git('status', '--porcelain', '--untracked-files=all', '--', 'Learning').splitlines()
              if line and not line[3:].endswith('.DS_Store')]
    if strays:
        raise SystemExit('Untracked files sit in the package: ' + ', '.join(strays[:6]) + '. Remove them; the package is read-only here.')
    tags = [t for t in git('tag', '--points-at', 'HEAD', 'learning-v*').splitlines() if t]
    tag = tags[0] if len(tags) == 1 else None
    tracked = [line for line in git('ls-files', '--', 'Learning').splitlines() if line]
    files = {path[len('Learning/'):]: sha256(source / path) for path in sorted(tracked)}
    if any(part == 'node_modules' for name in files for part in name.split('/')):
        raise SystemExit('The package carries node_modules; it must not.')
    contract = json.loads((package / 'host-contract.json').read_text())['hostContract']
    if not isinstance(contract, int) or contract < 1:
        raise SystemExit('host-contract.json must carry an integer hostContract of 1 or more.')
    return {'repository': repository, 'commit': revision, 'tag': tag, 'hostContract': contract, 'files': files}


def host_constant():
    match = re.search(r'static let version\s*=\s*(\d+)', swift_constant.read_text())
    if not match:
        raise SystemExit(f'{swift_constant} does not declare the Learning host contract version.')
    return int(match.group(1))


def pins():
    mine = json.loads((base / 'package.json').read_text()).get('dependencies', {})
    theirs = json.loads((package / 'package.json').read_text()).get('dependencies', {})
    return mine, theirs


def gitlink():
    entry = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-s', '--', 'Learn/Upstream'], text=True).split()
    return entry[1] if len(entry) >= 2 and entry[0] == '160000' else None


def write(allow_untagged=False):
    current = snapshot()
    if current['tag'] is None and not allow_untagged:
        tags = git('tag', '--points-at', 'HEAD', 'learning-v*').split()
        raise SystemExit('The pinned commit carries ' + (f"{len(tags)} learning-v tags" if tags else 'no learning-v tag')
                         + '; pin a tagged release (git -C Learn/Upstream fetch --tags), or pass --allow-untagged.')
    manifest_path.write_text(json.dumps(current, indent=2) + '\n')
    for name, target in copies.items():
        target.write_bytes((package / name).read_bytes())
    # Recording the pin stages the submodule entry too, so the repository, the manifest and the checkout agree at once.
    subprocess.check_call(['git', '-C', str(root), 'add', '--', 'Learn/Upstream'])
    print(f"Recorded Learning package {current['commit'][:8]}" + (f" ({current['tag']})" if current['tag'] else '')
          + f", {len(current['files'])} files, host contract {current['hostContract']}; copied {', '.join(copies)} into Content/Learn.")
    verify()


def verify():
    recorded = json.loads(manifest_path.read_text())
    current = snapshot()
    problems = []
    if current['commit'] != recorded['commit']:
        problems.append(f"the submodule is at {current['commit'][:8]} but the manifest records {recorded['commit'][:8]}")
    link = gitlink()
    if link and link != recorded['commit']:
        problems.append(f"the repository's Learn/Upstream entry is {link[:8]} but the manifest records {recorded['commit'][:8]}")
    missing = sorted(set(recorded['files']) - set(current['files']))
    extra = sorted(set(current['files']) - set(recorded['files']))
    changed = sorted(p for p in recorded['files'] if p in current['files'] and current['files'][p] != recorded['files'][p])
    for label, items in (('missing', missing), ('unrecorded', extra), ('changed', changed)):
        if items:
            problems.append(f"{label} in the package: {', '.join(items[:6])}{' ...' if len(items) > 6 else ''}")
    for name, target in copies.items():
        if not target.exists() or target.read_bytes() != (package / name).read_bytes():
            problems.append(f"{target.relative_to(root)} differs from the package's {name}; the page is edited in statisticalhelp and the pin moved, and --write replaces this copy with the package's")
    numbers = {'the package': current['hostContract'], 'the manifest': recorded.get('hostContract'), 'the Swift host': host_constant()}
    if len(set(numbers.values())) != 1:
        problems.append('host contract numbers differ: ' + ', '.join(f'{k} {v}' for k, v in numbers.items()))
    mine, theirs = pins()
    if mine != theirs:
        problems.append(f'Learn/package.json pins {mine} but the package pins {theirs}')
    if (base / 'pnpm-lock.yaml').read_bytes() != (package / 'pnpm-lock.yaml').read_bytes():
        problems.append("Learn/pnpm-lock.yaml differs from the package's lockfile; copy it and run pnpm install --frozen-lockfile in Learn")
    bundle = root / 'Content/Learn/app.js'
    if not bundle.exists() or not re.search(r'hostContract:\s*' + str(current['hostContract']) + r'\b', bundle.read_text(errors='replace')):
        problems.append(f"Content/Learn/app.js does not carry host contract {current['hostContract']}; run node Learn/build.mjs and commit the bundles")
    if problems:
        raise SystemExit('Learning package verification failed: ' + '; '.join(problems) + '.')
    print(f"Verified Learning package {recorded['commit'][:8]}" + (f" ({recorded['tag']})" if recorded.get('tag') else '')
          + f": {len(recorded['files'])} files, copies in Content/Learn, host contract {numbers['the package']}.")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--write', action='store_true', help='record the pin and copy the page shell and stylesheet')
    mode.add_argument('--verify', action='store_true', help='check the pin, the files, the copies and the contract')
    parser.add_argument('--allow-untagged', action='store_true', help='with --write: record a commit that carries no learning-v tag')
    args = parser.parse_args()
    write(args.allow_untagged) if args.write else verify()
