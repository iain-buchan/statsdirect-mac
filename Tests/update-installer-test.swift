import Foundation

@main struct UpdateInstallerTests {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("StatsDirect-update-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }

        try checkArchivePaths(in: folder)
        try checkReplacement(in: folder)
        try checkAttributes(in: folder)
        checkSupportedSystem()
        try checkStaleStaging(in: folder)
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

    private static func run(_ tool: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try! process.run()
        process.waitUntilExit()
        precondition(process.terminationStatus == 0, "\(tool) failed")
    }

    private static func hasAccessList(_ path: String) -> Bool {
        guard let list = acl_get_link_np(path, ACL_TYPE_EXTENDED) else { return false }
        defer { acl_free(UnsafeMutableRawPointer(list)) }
        var entry: acl_entry_t?
        return acl_get_entry(list, ACL_FIRST_ENTRY.rawValue, &entry) == 0
    }

    private static func checkAttributes(in folder: URL) throws {
        let manager = FileManager.default
        func app(_ name: String) throws -> URL {
            let app = folder.appendingPathComponent(name).appendingPathComponent("StatsDirect.app")
            try manager.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
            try Data("fixture".utf8).write(to: app.appendingPathComponent("Contents/file"))
            return app
        }
        try UpdateInstaller.checkAttributes(try app("plain"))
        let listed = try app("listed")
        run("/bin/chmod", ["+a", "everyone allow write", listed.appendingPathComponent("Contents/file").path])
        reject { try UpdateInstaller.checkAttributes(listed) }
        let marked = try app("marked")
        run("/usr/bin/xattr", ["-w", "com.apple.quarantine", "0083;00000000;Fixture;", marked.appendingPathComponent("Contents/file").path])
        reject { try UpdateInstaller.checkAttributes(marked) }
        let writable = try app("writable")
        run("/bin/chmod", ["g+w", writable.appendingPathComponent("Contents").path])
        reject { try UpdateInstaller.checkAttributes(writable) }
        let linked = try app("linked")
        try manager.linkItem(at: linked.appendingPathComponent("Contents/file"), to: linked.appendingPathComponent("Contents/twin"))
        reject { try UpdateInstaller.checkAttributes(linked) }
        let pointed = try app("pointed")
        try manager.createSymbolicLink(at: pointed.appendingPathComponent("Contents/link"), withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        reject { try UpdateInstaller.checkAttributes(pointed) }

        // ditto stores an access control list as an AppleDouble entry, and macOS's tar applies it on extraction.
        // Whatever the extractor does with it, an app that still carries the list must not pass.
        let archive = folder.appendingPathComponent("listed.zip")
        run("/usr/bin/ditto", ["-c", "-k", "--keepParent", listed.path, archive.path])
        let location = folder.appendingPathComponent("listed-extracted")
        try manager.createDirectory(at: location, withIntermediateDirectories: false)
        let extracted = try UpdateInstaller.extract(archive, in: location)
        if hasAccessList(extracted.appendingPathComponent("Contents/file").path) {
            reject { try UpdateInstaller.checkAttributes(extracted) }
        } else {
            try UpdateInstaller.checkAttributes(extracted)
        }
        print("PASS: an app with an access control list, a foreign attribute, group write permission, a hard link or a symbolic link is refused, also after extraction from a ZIP")
    }

    private static func checkSupportedSystem() {
        let mac = OperatingSystemVersion(majorVersion: 14, minorVersion: 6, patchVersion: 1)
        precondition(UpdateInstaller.supportsThisMac(minimum: nil, current: mac))
        precondition(UpdateInstaller.supportsThisMac(minimum: "14.0", current: mac))
        precondition(UpdateInstaller.supportsThisMac(minimum: "14.6.1", current: mac))
        precondition(!UpdateInstaller.supportsThisMac(minimum: "14.6.2", current: mac))
        precondition(!UpdateInstaller.supportsThisMac(minimum: "15", current: mac))
        precondition(!UpdateInstaller.supportsThisMac(minimum: "fourteen", current: mac))
        print("PASS: an update that needs a later macOS than this Mac has is refused")
    }

    private static func checkStaleStaging(in folder: URL) throws {
        let manager = FileManager.default
        let home = folder.appendingPathComponent("stale")
        let app = home.appendingPathComponent("StatsDirect.app")
        try manager.createDirectory(at: app, withIntermediateDirectories: true)
        let old = home.appendingPathComponent(".StatsDirect-update-" + UUID().uuidString)
        let fresh = home.appendingPathComponent(".StatsDirect-update-" + UUID().uuidString)
        let other = home.appendingPathComponent(".StatsDirect-update-notes")
        for item in [old, fresh, other] {
            try manager.createDirectory(at: item.appendingPathComponent("extracted"), withIntermediateDirectories: true)
        }
        let longAgo = Date().addingTimeInterval(-172_800)
        try manager.setAttributes([.modificationDate: longAgo], ofItemAtPath: old.path)
        try manager.setAttributes([.modificationDate: longAgo], ofItemAtPath: other.path)
        UpdateInstaller.removeStaleStaging(beside: app)
        precondition(!manager.fileExists(atPath: old.path))
        precondition(manager.fileExists(atPath: fresh.path))
        precondition(manager.fileExists(atPath: other.path))
        precondition(manager.fileExists(atPath: app.path))
        print("PASS: a staging folder left by an interrupted update is removed after a day; recent ones and other folders are kept")
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
