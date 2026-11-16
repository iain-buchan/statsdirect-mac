#!/usr/bin/env python3
"""Check a built StatsDirect.app, and optionally its symbols, before it is packaged.

  check-app-bundle.py <app> [--symbols <dSYM or folder>]... [--private <path>]... [--home <path>]

1. Every account can read the app: each folder is readable and searchable by all, each file readable by all, nothing is
   writable by group or others, and nothing carries setuid, setgid or the sticky bit. A file only its owner can read makes
   a signature check of the app fail ("Permission denied") for every other account on the Mac.
2. The app holds only folders and ordinary files, each file under one name: no symbolic link, no hard link, nothing else.
   The in-app installer refuses an update that holds any of them.
3. No separate .NET symbol file (.pdb) is in the app: the engine's symbols are embedded in its assembly.
4. With --private: no file in the app or the symbols names that path. Give the repository and the build area, so that a
   release does not publish the build Mac's folders. The path is looked for as UTF-8 and UTF-16, percent-encoded and with
   JSON's escaped slashes, in each file and inside the symbols embedded in a .NET assembly (which are compressed, and hold
   a source file's path as its separate parts). A match must end where the path ends: a longer name that merely begins
   with it is another folder. With --home: likewise for the build account's home folder, except in the bundled .NET
   runtime, which is Microsoft's own build and names its own build machine. A path of fewer than two folders cannot be
   told from ordinary text and is not searched for; the output says so.
"""
import argparse, os, stat, sys, zlib
from pathlib import Path
from urllib.parse import quote

RUNTIME = Path('Contents/Resources/Engine/dotnet')      # Microsoft's files, checked against the SDK's elsewhere
NAME_CHARACTERS = frozenset(b'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-')


def entries(root, faults, base):
    """Every folder, file and other entry under root (root first), found without following links. A folder that cannot be
    listed is reported and is still an entry itself."""
    pending = [root]
    while pending:
        folder = pending.pop()
        yield folder
        try:
            children = sorted(os.scandir(folder), key=lambda entry: entry.name)
        except OSError as error:
            faults.append('folder that cannot be listed (%s): %s' % (error.strerror, folder.relative_to(base)))
            continue
        for child in children:
            path = Path(child.path)
            if child.is_dir(follow_symlinks=False): pending.append(path)
            else: yield path


def permission_faults(app):
    """The faults, and the number of files and folders looked at."""
    faults = []; count = 0
    for path in entries(app, faults, app.parent):
        shown = str(path.relative_to(app.parent)); count += 1
        try:
            info = path.lstat()
        except OSError as error:               # inside a folder that can be listed but not entered
            faults.append('entry that cannot be examined (%s): %s' % (error.strerror, shown)); continue
        mode = stat.S_IMODE(info.st_mode)
        if stat.S_ISLNK(info.st_mode):
            faults.append('symbolic link: %s' % shown); continue
        if stat.S_ISDIR(info.st_mode):
            if mode & 0o555 != 0o555: faults.append('folder not open to every account (%04o): %s' % (mode, shown))
        elif stat.S_ISREG(info.st_mode):
            if mode & 0o444 != 0o444: faults.append('file not readable by every account (%04o): %s' % (mode, shown))
            if info.st_nlink > 1: faults.append('file with %d names (hard links): %s' % (info.st_nlink, shown))
        else:
            faults.append('neither a file nor a folder: %s' % shown)
        if mode & 0o022: faults.append('writable by group or others (%04o): %s' % (mode, shown))
        if mode & 0o7000: faults.append('setuid, setgid or sticky (%04o): %s' % (mode, shown))
    return faults, count


def needles(path):
    """The forms a path is looked for in, each with the width of one character in it and whether that is big-endian."""
    text = str(path).rstrip('/')
    forms = {(text.encode('utf-8'), 1, False), (text.encode('utf-16-le'), 2, False), (text.encode('utf-16-be'), 2, True),
             (quote(text).encode('ascii'), 1, False), (text.replace('/', '\\/').encode('utf-8'), 1, False)}
    return sorted(forms)


def named(data, forms):
    """Whether data names the path: one of its forms occurs and is not followed by a further name character."""
    for needle, width, big in forms:
        at = data.find(needle)
        while at >= 0:
            after = data[at + len(needle):at + len(needle) + width]
            if width == 1: follows = after[0] if after else None
            else: follows = (after[1] if big else after[0]) if len(after) == 2 and (after[0] if big else after[1]) == 0 else None
            if follows is None or follows not in NAME_CHARACTERS: return True
            at = data.find(needle, at + 1)
    return False


def embedded_symbols(data):
    """The portable symbol files embedded in a .NET assembly: 'MPDB', the unpacked size, then a raw deflate stream."""
    found = []; at = data.find(b'MPDB') if data[:2] == b'MZ' else -1
    while at >= 0:
        try:
            symbols = zlib.decompressobj(-15).decompress(data[at + 8:])
            if symbols[:4] == b'BSJB' and len(symbols) == int.from_bytes(data[at + 4:at + 8], 'little'): found.append(symbols)
        except zlib.error:
            pass
        at = data.find(b'MPDB', at + 4)
    return found


def names_in_symbols(symbols, path):
    """A portable symbol file stores each folder and file name of a source path once, as its own length-prefixed string.
    A source file under 'path' is there only if every part of 'path' is."""
    parts = [part.encode('utf-8') for part in Path(path).parts if part != '/']
    return bool(parts) and all(len(part) < 128 and bytes([len(part)]) + part in symbols for part in parts)


def path_faults(root, base, private, home, report_links):
    """Search every file under root. report_links: a symbolic link is a fault here (among the symbols, which are packed as
    they are; the app's own links are already reported with its permissions)."""
    faults = []; scanned = 0
    for path in entries(root, faults, base):
        shown = path.relative_to(base)
        try:
            kind = path.lstat().st_mode
            if stat.S_ISLNK(kind):
                if report_links: faults.append('symbolic link: %s' % shown)
                continue
            if not stat.S_ISREG(kind): continue
            data = path.read_bytes()
        except OSError as error:
            faults.append('file that cannot be read (%s): %s' % (error.strerror, shown)); continue
        scanned += 1
        symbols = embedded_symbols(data)
        for label, forms, folder in private + ([] if path.relative_to(root).is_relative_to(RUNTIME) else home):
            if named(data, forms):
                faults.append('names %s: %s' % (label, shown))
            elif any(named(one, forms) or names_in_symbols(one, folder) for one in symbols):
                faults.append('its embedded symbols name %s: %s' % (label, shown))
    return faults, scanned


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('app', type=Path)
    parser.add_argument('--symbols', action='append', default=[], type=Path)
    parser.add_argument('--private', action='append', default=[], type=Path)
    parser.add_argument('--home', type=Path)
    args = parser.parse_args()
    app = args.app.resolve()
    if not (app / 'Contents/Info.plist').is_file():
        sys.exit('not an app bundle: %s' % app)
    faults, count = permission_faults(app)
    faults += ['a separate .NET symbol file is in the app: %s' % p.relative_to(app.parent) for p in sorted(app.rglob('*')) if p.suffix.lower() == '.pdb']
    searchable = lambda path: len(Path(path).parts) >= 3                   # "/", a folder and one more
    for path in [p for p in list(dict.fromkeys(args.private)) + ([args.home] if args.home else []) if not searchable(p)]:
        print('NOTE: %s is too short a path to tell from ordinary text: it was not searched for' % path)
    private = [('the build folder ' + str(p), needles(p), p) for p in dict.fromkeys(args.private) if searchable(p)]
    home = [('the build account\'s home folder', needles(args.home), args.home)] if args.home and searchable(args.home) else []
    scanned = 0
    if private or home:
        for folder in [app] + [s.resolve() for s in args.symbols]:
            if not folder.is_dir(): sys.exit('no such folder: %s' % folder)
            found, n = path_faults(folder, folder.parent, private, home, report_links=folder != app); scanned += n
            faults += [fault for fault in found if fault not in faults]
    if faults:
        for fault in faults[:40]: print('FAIL: ' + fault, file=sys.stderr)
        if len(faults) > 40: print('FAIL: and %d more' % (len(faults) - 40), file=sys.stderr)
        sys.exit(1)
    print('PASS: all %d files and folders of %s are readable by every account, none writable by others; no link, no .pdb' % (count, app.name))
    if private or home:
        print('PASS: none of %d files in the app%s names the build folders%s' % (
            scanned, ' and its symbols' if args.symbols else '', ' or the build account\'s home folder' if home else ''))


if __name__ == '__main__':
    main()
