#!/usr/bin/env python3
"""Scripts/check-app-bundle.py must refuse each fault it exists to catch, and pass a clean bundle.

The first faults are the ones StatsDirect for Mac 1.1.2 and 1.1.3 shipped with: a file only its owner could read (a
signature check then failed for every other account), separate .NET symbol files, and the build Mac's folders written into
the binaries and symbols. The others are what the in-app installer refuses in an update, and the ways a path can hide.
"""
import os, subprocess, sys, tempfile, unittest, zlib
from pathlib import Path
from urllib.parse import quote

CHECK = Path(__file__).resolve().parents[1] / 'Scripts/check-app-bundle.py'
PRIVATE = '/Users/someone/Library/Application Support/build area/statsdirect-mac'
HOME = '/Users/someone'


def blob(text):
    return bytes([len(text)]) + text.encode()


def assembly(source_path, text=b''):
    """Enough of a .NET assembly for the check: the MZ mark and one embedded portable symbol file naming a source path
    part by part, and holding any further text as it stands (as a Source Link map would be)."""
    symbols = b'BSJB' + b'\0' * 12 + b''.join(blob(part) for part in Path(source_path).parts if part != '/') + text
    packed = zlib.compressobj(wbits=-15); stream = packed.compress(symbols) + packed.flush()
    return b'MZ' + b'\0' * 62 + b'MPDB' + len(symbols).to_bytes(4, 'little') + stream + b'\0' * 16


class BundleCheck(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix='statsdirect-bundle-check-')
        self.addCleanup(self.folder.cleanup)
        self.app = Path(self.folder.name) / 'StatsDirect.app'
        self.symbols = Path(self.folder.name) / 'StatsDirect.app.dSYM'
        for name, data in {'Contents/Info.plist': b'<plist/>', 'Contents/MacOS/StatsDirect': b'\xcf\xfa\xed\xfe code',
                           'Contents/Resources/content-build-input.json': b'{}',
                           'Contents/Resources/Engine/StatsDirect.Headless.dll': assembly('StatsDirectUI/Builtins/Parametric.cs'),
                           'Contents/Resources/Engine/dotnet/shared/libcoreclr.dylib': b'built at ' + HOME.encode() + b'/work/1/s/src'}.items():
            self.write(self.app / name, data)
        self.write(self.symbols / 'Contents/Resources/DWARF/StatsDirect', b'DW_AT_comp_dir (".") Sources/main.swift')
        os.chmod(self.app / 'Contents/MacOS/StatsDirect', 0o755)

    def write(self, path, data, mode=0o644):
        path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data); os.chmod(path, mode)

    def run_check(self, *extra):
        return subprocess.run([sys.executable, str(CHECK), str(self.app), '--symbols', str(self.symbols), '--private', PRIVATE, '--home', HOME, *extra],
                              capture_output=True, text=True)

    def refused(self, expected, *extra):
        result = self.run_check(*extra)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(expected, result.stderr)
        self.assertNotIn('Traceback', result.stderr)

    def passes(self, *extra):
        result = self.run_check(*extra)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def test_clean_bundle_passes(self):
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('readable by every account', result.stdout)
        self.assertIn('names the build folders', result.stdout)

    def test_file_only_its_owner_can_read(self):
        os.chmod(self.app / 'Contents/Resources/content-build-input.json', 0o600)
        self.refused('file not readable by every account (0600): StatsDirect.app/Contents/Resources/content-build-input.json')

    def test_folder_closed_to_other_accounts(self):
        os.chmod(self.app / 'Contents/Resources/Engine', 0o700)
        self.addCleanup(os.chmod, self.app / 'Contents/Resources/Engine', 0o755)
        self.refused('folder not open to every account (0700): StatsDirect.app/Contents/Resources/Engine')

    def test_writable_by_others(self):
        os.chmod(self.app / 'Contents/Info.plist', 0o666)
        self.refused('writable by group or others (0666): StatsDirect.app/Contents/Info.plist')

    def test_separate_symbol_file(self):
        self.write(self.app / 'Contents/Resources/Engine/NPOI.Core.pdb', b'BSJB')
        self.refused('a separate .NET symbol file is in the app: StatsDirect.app/Contents/Resources/Engine/NPOI.Core.pdb')

    def test_build_folder_in_a_binary(self):
        self.write(self.app / 'Contents/MacOS/StatsDirect', b'\xcf\xfa\xed\xfe ' + PRIVATE.encode() + b'/Sources/', 0o755)
        self.refused('names the build folder ' + PRIVATE + ': StatsDirect.app/Contents/MacOS/StatsDirect')

    def test_build_folder_as_utf16(self):
        self.write(self.app / 'Contents/Resources/Engine/Other.dll', b'MZ' + (PRIVATE + '/obj/x.cs').encode('utf-16-le'))
        self.refused('StatsDirect.app/Contents/Resources/Engine/Other.dll')

    def test_build_folder_in_the_symbols(self):
        self.write(self.symbols / 'Contents/Resources/Relocations/aarch64/StatsDirect.yml', ("binary-path: '%s/StatsDirect.app/Contents/MacOS/StatsDirect'\n" % PRIVATE).encode())
        self.refused('StatsDirect.app.dSYM/Contents/Resources/Relocations/aarch64/StatsDirect.yml')

    def test_home_folder_outside_the_runtime(self):
        self.write(self.app / 'Contents/Resources/Engine/libStatsDirectText.dylib', b'include ' + HOME.encode() + b'/dotnet/packs/native/hostfxr.h')
        self.refused("names the build account's home folder: StatsDirect.app/Contents/Resources/Engine/libStatsDirectText.dylib")

    def test_source_path_in_embedded_symbols(self):
        self.write(self.app / 'Contents/Resources/Engine/StatsDirect.Headless.dll', assembly(PRIVATE + '/FullEngine/Upstream/StatsDirectUI/Builtins/Parametric.cs'))
        self.refused('its embedded symbols name the build folder ' + PRIVATE + ': StatsDirect.app/Contents/Resources/Engine/StatsDirect.Headless.dll')

    def test_path_as_plain_text_inside_embedded_symbols(self):
        # What Source Link writes: the build folder as a key of its map, not as the parts of a source file's name.
        self.write(self.app / 'Contents/Resources/Engine/StatsDirect.Headless.dll',
                   assembly('StatsDirectUI/Builtins/Parametric.cs', ('{"documents":{"%s/*":"https://raw.example/*"}}' % PRIVATE).encode()))
        self.refused('its embedded symbols name the build folder ' + PRIVATE + ': StatsDirect.app/Contents/Resources/Engine/StatsDirect.Headless.dll')

    def test_embedded_symbols_sharing_only_some_folder_names_pass(self):
        # 'Users', 'Library' and 'Application Support' are ordinary names: only the whole path identifies the build folder.
        self.write(self.app / 'Contents/Resources/Engine/StatsDirect.Headless.dll', assembly('Users/Library/Application Support/Guide.cs'))
        self.passes()

    def test_a_longer_name_that_begins_with_the_path_is_another_folder(self):
        self.write(self.app / 'Contents/Resources/Content/mml3.sef.json', b'"file://' + HOME.encode() + b'-else/Desktop/MathJax/mml3.xsl"')
        self.passes()
        # and for the build folder itself, searched for without the home folder that contains it
        self.write(self.app / 'Contents/Resources/Content/other.json', (PRIVATE + '2/Sources/main.swift').encode('utf-16-le'))
        only = [sys.executable, str(CHECK), str(self.app), '--private', PRIVATE]
        self.assertEqual(subprocess.run(only, capture_output=True, text=True).returncode, 0)
        self.write(self.app / 'Contents/Resources/Content/other.json', (PRIVATE + '/Sources/main.swift').encode('utf-16-le'))
        self.assertEqual(subprocess.run(only, capture_output=True, text=True).returncode, 1)

    def test_path_percent_encoded_escaped_or_big_endian(self):
        for name, data in {'encoded.json': quote(PRIVATE).encode() + b'/Sources', 'escaped.json': PRIVATE.replace('/', '\\/').encode() + b'\\/Sources',
                           'big-endian.bin': (PRIVATE + '/Sources').encode('utf-16-be')}.items():
            path = self.app / 'Contents/Resources/Content' / name
            self.write(path, data)
            self.refused('names the build folder ' + PRIVATE + ': StatsDirect.app/Contents/Resources/Content/' + name)
            path.unlink()

    def test_folder_that_cannot_be_listed(self):
        hidden = self.app / 'Contents/Resources/Hidden'
        self.write(hidden / 'secret.json', b'{}', 0o600)
        for mode in (0o000, 0o300):
            os.chmod(hidden, mode)
            self.addCleanup(os.chmod, hidden, 0o755)
            self.refused('folder not open to every account (%04o): StatsDirect.app/Contents/Resources/Hidden' % mode)
            self.refused('folder that cannot be listed (Permission denied): StatsDirect.app/Contents/Resources/Hidden')

    def test_folder_that_can_be_listed_but_not_entered(self):
        hidden = self.app / 'Contents/Resources/Shut'
        self.write(hidden / 'a.json', b'{}')
        for mode in (0o600, 0o400, 0o644):
            os.chmod(hidden, mode)
            self.addCleanup(os.chmod, hidden, 0o755)
            self.refused('folder not open to every account (%04o): StatsDirect.app/Contents/Resources/Shut' % mode)
            self.refused('entry that cannot be examined (Permission denied): StatsDirect.app/Contents/Resources/Shut/a.json')
        os.chmod(hidden, 0o755)
        shut = self.symbols / 'Contents/Resources/Shut'
        self.write(shut / 'map.yml', ("binary-path: '%s/StatsDirect'" % PRIVATE).encode())
        os.chmod(shut, 0o600)
        self.addCleanup(os.chmod, shut, 0o755)
        self.refused('file that cannot be read (Permission denied): StatsDirect.app.dSYM/Contents/Resources/Shut/map.yml')

    def test_file_group_or_others_cannot_read(self):
        for mode in (0o640, 0o604):
            os.chmod(self.app / 'Contents/Resources/content-build-input.json', mode)
            self.refused('file not readable by every account (%04o): StatsDirect.app/Contents/Resources/content-build-input.json' % mode)

    def test_folder_group_cannot_search_or_others_cannot_read(self):
        for mode in (0o745, 0o751):
            os.chmod(self.app / 'Contents/Resources/Engine', mode)
            self.refused('folder not open to every account (%04o): StatsDirect.app/Contents/Resources/Engine' % mode)
        os.chmod(self.app / 'Contents/Resources/Engine', 0o755)

    def test_setgid_and_sticky(self):
        os.chmod(self.app / 'Contents/MacOS/StatsDirect', 0o2755)
        self.refused('setuid, setgid or sticky (2755): StatsDirect.app/Contents/MacOS/StatsDirect')
        os.chmod(self.app / 'Contents/MacOS/StatsDirect', 0o755)
        os.chmod(self.app / 'Contents/Resources', 0o1755)
        self.refused('setuid, setgid or sticky (1755): StatsDirect.app/Contents/Resources')

    def test_symbol_file_with_a_capital_suffix(self):
        self.write(self.app / 'Contents/Resources/Engine/NPOI.Core.PDB', b'BSJB')
        self.refused('a separate .NET symbol file is in the app: StatsDirect.app/Contents/Resources/Engine/NPOI.Core.PDB')

    def test_symbolic_link_among_the_symbols(self):
        os.symlink(PRIVATE + '/StatsDirect.app/Contents/MacOS/StatsDirect', self.symbols / 'Contents/Resources/DWARF/link')
        self.refused('symbolic link: StatsDirect.app.dSYM/Contents/Resources/DWARF/link')

    def test_private_path_inside_the_bundled_runtime(self):
        # The runtime may name Microsoft's build machine (the home folder rule skips it); it may not name ours.
        self.write(self.app / 'Contents/Resources/Engine/dotnet/shared/libcoreclr.dylib', b'built at ' + PRIVATE.encode() + b'/obj')
        self.refused('names the build folder ' + PRIVATE + ': StatsDirect.app/Contents/Resources/Engine/dotnet/shared/libcoreclr.dylib')

    def test_path_at_the_end_of_big_endian_text_and_after_a_longer_name(self):
        path = self.app / 'Contents/Resources/Content/end.bin'
        self.write(path, PRIVATE.encode('utf-16-be'))            # only the big-endian form matches text that ends at the path
        self.refused('names the build folder ' + PRIVATE + ': StatsDirect.app/Contents/Resources/Content/end.bin')
        self.write(path, PRIVATE.encode() + b'-x/Sources ' + PRIVATE.encode() + b'/Sources')     # another folder first, then ours
        self.refused('names the build folder ' + PRIVATE + ': StatsDirect.app/Contents/Resources/Content/end.bin')
        path.unlink()
        only = [sys.executable, str(CHECK), str(self.app), '--private', PRIVATE]
        for other in ('.bak', '_x', '2', 'B'):                    # each continues the last folder's name: another folder
            self.write(path, PRIVATE.encode() + other.encode() + b'/Sources')
            self.assertEqual(subprocess.run(only, capture_output=True, text=True).returncode, 0, other)

    def test_only_real_embedded_symbols_are_read(self):
        # 'MPDB' followed by something that is not a symbol file, and a file that is not an assembly: neither is unpacked.
        packed = zlib.compressobj(wbits=-15); stream = packed.compress(b'NOPE' + b''.join(blob(part) for part in Path(PRIVATE).parts if part != '/')) + packed.flush()
        self.write(self.app / 'Contents/Resources/Engine/Odd.dll', b'MZ' + b'\0' * 62 + b'MPDB' + (4).to_bytes(4, 'little') + stream)
        self.write(self.app / 'Contents/Resources/Engine/notes.bin', assembly(PRIVATE + '/x.cs')[2:])
        self.passes()

    def test_file_that_cannot_be_read_is_a_fault_not_a_crash(self):
        os.chmod(self.app / 'Contents/Resources/content-build-input.json', 0o000)
        self.addCleanup(os.chmod, self.app / 'Contents/Resources/content-build-input.json', 0o644)
        self.refused('file that cannot be read (Permission denied): StatsDirect.app/Contents/Resources/content-build-input.json')

    def test_folder_others_cannot_search(self):
        os.chmod(self.app / 'Contents/Resources/Engine', 0o754)
        self.refused('folder not open to every account (0754): StatsDirect.app/Contents/Resources/Engine')

    def test_writable_by_group_alone_or_by_others_alone(self):
        for mode in (0o664, 0o646):
            os.chmod(self.app / 'Contents/Info.plist', mode)
            self.refused('writable by group or others (%04o): StatsDirect.app/Contents/Info.plist' % mode)

    def test_set_user_bit(self):
        os.chmod(self.app / 'Contents/MacOS/StatsDirect', 0o4755)
        self.refused('setuid, setgid or sticky (4755): StatsDirect.app/Contents/MacOS/StatsDirect')

    def test_symbolic_link(self):
        os.symlink('StatsDirect', self.app / 'Contents/MacOS/Alias')
        self.refused('symbolic link: StatsDirect.app/Contents/MacOS/Alias')

    def test_hard_link(self):
        os.link(self.app / 'Contents/Info.plist', self.app / 'Contents/Resources/Info-again.plist')
        self.refused('file with 2 names (hard links): StatsDirect.app/Contents/Info.plist')

    def test_neither_a_file_nor_a_folder(self):
        os.mkfifo(self.app / 'Contents/Resources/pipe', 0o644)
        self.refused('neither a file nor a folder: StatsDirect.app/Contents/Resources/pipe')

    def test_missing_symbols_folder_is_an_error(self):
        result = self.run_check('--symbols', str(self.symbols.parent / 'Missing.dSYM'))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('no such folder', result.stderr)

    def test_too_short_a_path_is_not_searched_for_and_says_so(self):
        output = self.passes('--private', '/Users')
        self.assertIn('NOTE: /Users is too short a path', output)
        self.write(self.app / 'Contents/MacOS/StatsDirect', b'\xcf\xfa\xed\xfe ' + PRIVATE.encode(), 0o755)
        self.refused('names the build folder ' + PRIVATE, '--private', '/Users')      # the real path is still searched for

    def test_permissions_alone_without_private_paths(self):
        self.write(self.app / 'Contents/MacOS/StatsDirect', b'\xcf\xfa\xed\xfe ' + PRIVATE.encode(), 0o755)
        result = subprocess.run([sys.executable, str(CHECK), str(self.app)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)       # as package-release.sh runs it on the signed app


if __name__ == '__main__':
    unittest.main(verbosity=2)
