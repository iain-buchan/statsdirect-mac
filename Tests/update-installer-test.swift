import Foundation

@main struct UpdateInstallerTests {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StatsDirect-update-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }

        try checkArchivePaths(in: folder)
        try checkReplacement(in: folder)
        if CommandLine.arguments.count == 3 {
            try checkSignedReleases(in: folder, installedZip: CommandLine.arguments[1], updateZip: CommandLine.arguments[2])
        }
    }

    private static func reject(_ action: () throws -> Void) {
        do { try action() }
        catch { return }
        fatalError("Accepted an invalid update")
    }

    private static func checkArchivePaths(in folder: URL) throws {
        let python = Process()
        python.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        python.arguments = ["python3", "-c", """
        import stat, sys, zipfile
        from pathlib import Path
        folder = Path(sys.argv[1])
        for name, path in [('valid', 'StatsDirect.app/marker'),
                           ('escape', '../escaped-marker'),
                           ('nested-escape', 'StatsDirect.app/../../escaped-marker'),
                           ('extra', 'extra-file')]:
            with zipfile.ZipFile(folder / (name + '.zip'), 'w') as archive:
                archive.writestr('StatsDirect.app/marker', 'fixture')
                if name != 'valid':
                    archive.writestr(path, 'unexpected')
        with zipfile.ZipFile(folder / 'symlink.zip', 'w') as archive:
            link = zipfile.ZipInfo('StatsDirect.app/escape')
            link.create_system = 3
            link.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(link, '..')
            archive.writestr('StatsDirect.app/escape/escaped-marker', 'unexpected')
        """, folder.path]
        try python.run()
        python.waitUntilExit()
        precondition(python.terminationStatus == 0)
        for name in ["valid", "escape", "nested-escape", "extra", "symlink"] {
            let location = folder.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: location, withIntermediateDirectories: false)
            let zip = folder.appendingPathComponent(name + ".zip")
            if name == "valid" {
                let app = try UpdateInstaller.extract(zip, in: location)
                precondition(FileManager.default.fileExists(atPath: app.appendingPathComponent("marker").path))
            } else {
                reject { _ = try UpdateInstaller.extract(zip, in: location) }
                precondition(!FileManager.default.fileExists(atPath: location.appendingPathComponent("escaped-marker").path))
                precondition(!FileManager.default.fileExists(atPath: location.appendingPathComponent("extracted/escaped-marker").path))
            }
        }
        print("PASS: the ZIP extractor rejects traversal, symlink escapes and additional top-level files")
    }

    private static func checkReplacement(in folder: URL) throws {
        let target = folder.appendingPathComponent("Installed.app")
        let candidate = folder.appendingPathComponent("Replacement.app")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: false)
        let old = target.appendingPathComponent("old")
        let new = target.appendingPathComponent("new")
        try Data().write(to: old)
        try Data().write(to: candidate.appendingPathComponent("new"))
        reject {
            try UpdateInstaller.replace(target, with: candidate) {
                precondition(FileManager.default.fileExists(atPath: new.path))
                throw UpdateService.failure("Simulated relaunch failure")
            }
        }
        precondition(FileManager.default.fileExists(atPath: old.path))
        try UpdateInstaller.replace(target, with: candidate) {
            precondition(FileManager.default.fileExists(atPath: new.path))
            precondition(FileManager.default.fileExists(atPath: candidate.appendingPathComponent("old").path))
        }
        precondition(FileManager.default.fileExists(atPath: new.path))
        print("PASS: installation swaps whole bundles and restores the original if relaunch fails")
    }

    private static func checkSignedReleases(in folder: URL, installedZip: String, updateZip: String) throws {
        func expand(_ zip: String, as name: String) throws -> URL {
            let location = folder.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: location, withIntermediateDirectories: false)
            return try UpdateInstaller.extract(URL(fileURLWithPath: zip), in: location)
        }
        func version(_ url: URL) -> String {
            Bundle(url: url)!.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        }
        let installed = try expand(installedZip, as: "signed-installation")
        let candidate = try expand(updateZip, as: "signed-update")
        let oldVersion = version(installed)
        let newVersion = version(candidate)
        try UpdateInstaller.verify(candidate, version: "v" + newVersion, replacing: installed)
        reject { try UpdateInstaller.verify(candidate, version: "v999.0.0", replacing: installed) }
        reject { try UpdateInstaller.verify(installed, version: oldVersion, replacing: candidate) }
        let tampered = try expand(updateZip, as: "tampered-update")
        try Data("unexpected".utf8).write(to: tampered.appendingPathComponent("Contents/Resources/unsealed.txt"))
        reject { try UpdateInstaller.verify(tampered, version: newVersion, replacing: installed) }
        try UpdateInstaller.replace(installed, with: candidate) {
            // Read the replaced files directly because Foundation caches bundle information.
            let plist = try Data(contentsOf: installed.appendingPathComponent("Contents/Info.plist"))
            let values = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
            precondition(values?["CFBundleShortVersionString"] as? String == newVersion)
        }
        print("PASS: installed signed \(oldVersion) → \(newVersion) in an isolated folder, with publisher, notarisation, version and tampering checks")
    }
}
