# Signing and notarising a StatsDirect for Mac release

A release is built and tested from a clean clone of the release commit, then signed with StatsDirect Limited's
Developer ID and notarised by Apple on the release Mac, checked, and published. Nothing in this repository or its
workflows holds a certificate or a password.

## Release policy

- Only a Developer ID signed, notarised, stapled and verified build may become GitHub's **Latest** stable release,
  be offered through **Help → Check for Updates**, or replace the public download linked from
  [StatsDirect downloads](https://www.statsdirect.com/download.aspx).
- Until then, publish the candidate explicitly as a **pre-release** with `make_latest: false` for checking. Never
  publish an unsigned candidate as a stable release, overwrite the live release's assets, or replace the stable
  `StatsDirect-macOS-arm64.zip` alias with it.
- **A published release ZIP is never replaced.** From 1.1.2 an installed copy downloads
  `StatsDirect-<version>-macOS-arm64.zip` from the release itself and checks its size and SHA-256 against GitHub's
  record of that asset. A copy part-way through an update would fail that check if the file changed, and a copy
  that already has a version is never offered it again, so a replaced ZIP would leave two different apps under one
  version number. Upload the notarised ZIP once; if it is wrong, withdraw the release and cut a new version.
- The Mac and Windows versions are kept at functional parity, so a Mac release carries no separate list of changes:
  its notes name the Windows version whose behaviour it matches and point to
  [StatsDirect revisions](https://www.statsdirect.com/Revisions.aspx), adding only what is Mac-specific
  (installation, signing, the engine revision). Complete the release tests and the CI checks on the release commit
  before signing. A planned date alone does not authorise promotion: verify the published pre-release first.
- **Releases from 1.1.2 (13 November 2026) are signed by StatsDirect Limited**, team `675296U8XP`. Releases 1.1.0 and
  1.1.1 were signed by the University of Liverpool, team `ULCPE837C7`, through its IT Services. Versions 1.1.0 and
  1.1.1 have no in-app installer: they show a notice whose View Update button opens the release page, and are replaced
  by hand once. From 1.1.2 the in-app installer replaces a copy that is in a folder its user may change, and accepts
  only an update signed by the team that signed the running copy. Record the signer and team in `BUILD-INFO.txt`. Do
  not change the signing team again without planning for a manual step.

## What you need

- An Apple Silicon Mac with macOS 14 or later and the Xcode command line tools (`xcode-select --install`), which
  provide `codesign`, `xcrun notarytool` and `xcrun stapler`.
- Everything the README's build section needs: the .NET 10 SDK, Node with pnpm, Python 3, and R for the tests.
- The **Developer ID Application** certificate of StatsDirect Limited's Apple Developer account, with its private
  key, in your login keychain. `security find-identity -v -p codesigning` must list it as valid:
  `Developer ID Application: STATSDIRECT LIMITED (675296U8XP)`. Use the identity exactly as that line prints it.
  Only the account holder can create this certificate. Make it at developer.apple.com under Certificates, from a
  signing request made in Keychain Access on the Mac that will sign; Xcode refused to create it here, even for the
  account holder.
- A notarytool keychain profile, made once from an Apple ID that is a member of the team, with an app-specific password
  from account.apple.com (not the Apple ID password), or from an App Store Connect API key:

  ```sh
  xcrun notarytool store-credentials StatsDirect-notary --apple-id <the team's Apple ID> --team-id 675296U8XP
  # or
  xcrun notarytool store-credentials StatsDirect-notary --key AuthKey_XXXXXXXX.p8 --key-id XXXXXXXX --issuer <issuer id>
  ```

- A fresh clone at the exact release commit, with its submodules, including `Scripts/sign-app.sh`,
  `StatsDirect.entitlements` and `RConsoleWorker.entitlements`. Do not use an older release's signing script:

  ```sh
  git clone --recurse-submodules https://github.com/iain-buchan/statsdirect-mac.git
  cd statsdirect-mac
  git checkout RELEASE_COMMIT  # the commit the release tag will name, recorded in BUILD-INFO.txt
  git submodule update --init --recursive
  ```

## Steps

1. In the fresh clone, install the JavaScript dependencies from the lockfiles (`pnpm install --frozen-lockfile` in
   `Grid`, `Report` and `Learn`), build with `./build.sh`, and run the release tests on the built app, as CI does.
   Rebuilding the bundles must leave the tree unchanged. The app bundles the .NET runtime of the SDK that built it:
   use the SDK whose runtime matches the security update the Windows setup ships.
2. Package the tested, unsigned build with
   `Scripts/package-release.sh <app> <symbols folder> <version> <output folder> --unsigned` and keep it and its
   symbols: the signed app is compared with it file by file in step 4.
3. Expand the unsigned ZIP of step 2 into a new folder and work on that copy, so that the tested build stays as it
   is. Sign every Mach-O inside the bundle and then the bundle, with the hardened runtime, the entitlements and a
   secure timestamp, submit to Apple, wait for the verdict, staple the ticket and validate it, in one command
   (Apple's answer usually takes one to two minutes; the first submission of a new team can take hours):

   ```sh
   ditto -x -k <output folder>/StatsDirect-<version>-macOS-arm64-unsigned.zip signed
   Scripts/sign-app.sh "$PWD/signed/StatsDirect.app" "Developer ID Application: STATSDIRECT LIMITED (675296U8XP)" --notarize StatsDirect-notary
   ```

   The script signs the .NET runtime's libraries under `Contents/Resources/Engine` as well as the app's own code (a plain
   `codesign --deep` would miss them), verifies the signature strictly, checks that the `com.apple.security.cs.allow-jit`
   entitlement is in it. Only `Contents/MacOS/RConsoleWorker` receives the separate worker entitlements described below;
   its signature is checked too. The script ends with `spctl --assess` accepting the
   app. If Apple's verdict is "Invalid", `xcrun notarytool log <submission id> --keychain-profile StatsDirect-notary`
   names the file at fault.
4. Check what you will ship:

   ```sh
   codesign --verify --deep --strict --verbose=2 StatsDirect.app
   codesign --display --entitlements - StatsDirect.app/Contents/MacOS/RConsoleWorker
   spctl --assess --type exec --verbose=2 StatsDirect.app      # "accepted", source=Notarized Developer ID
   xcrun stapler validate StatsDirect.app
   /usr/bin/syspolicy_check distribution StatsDirect.app       # exit 0: the notarisation check the in-app installer also makes
   open StatsDirect.app                                        # it launches, Help → About shows the version
   ```

   Apart from signatures and the stapled ticket, the signed app must equal the tested build file by file.

5. Package the signed app once and record its hash. The ZIP must carry no resource forks, extended attributes or
   access control lists: the in-app installer refuses an update that arrives with any, as it refuses symbolic links,
   hard links, files other users may write and set-user bits.

   ```sh
   ditto -c -k --norsrc --noextattr --keepParent StatsDirect.app StatsDirect-<version>-macOS-arm64.zip
   shasum -a 256 StatsDirect-<version>-macOS-arm64.zip
   ```

   Then apply the installer's own checks to that ZIP as an update of the previous release, before anything is
   uploaded: build `.build/update-installer-test` as `ci.yml` does and run it with two arguments. It unpacks both,
   verifies the new app against the previous one (attributes, signing team, version, notarisation) and exchanges them
   in a temporary folder.

   ```sh
   .build/update-installer-test <the previous release's ZIP> StatsDirect-<version>-macOS-arm64.zip
   ```

6. Publish a **pre-release** (`prerelease: true`, `make_latest: false`) on the tag `v<version>` at the release commit,
   with `StatsDirect-<version>-macOS-arm64.zip`, the same file again as `StatsDirect-macOS-arm64.zip` (the name the
   website links), the symbols ZIP of the tested build (the signed app's code is the same build, so its symbols still
   match), `StatsDirect-<version>-SHA256SUMS.txt` written afresh for the three ZIPs being published (step 2's file
   lists the unsigned ZIP), and `StatsDirect-<version>-BUILD-INFO.txt` written afresh, saying who signed and notarised
   it and when. Then check it as a user would: download the ZIP from the release, compare its size and SHA-256 with
   the checksum file and with GitHub's digest, see Gatekeeper accept a quarantined copy, and run the app, an analysis
   and a real R command with a chart.
7. Promote: in one change set the release to stable and explicitly **Latest**. That is the moment installed copies
   are offered the release: **Help → Check for Updates** and the check at start-up use GitHub's latest stable release
   and exclude drafts and pre-releases. The website's download link names
   `releases/latest/download/StatsDirect-macOS-arm64.zip`, so it follows by itself; only the version and date shown on
   the download page are edited. Check the link before and after, keep the previous releases' assets intact, and
   confirm with an installed copy of the previous version that it offers, installs and reopens as the new one.

## Why these choices

- The app is signed for distribution outside the App Store (Developer ID), so no provisioning profile or App Store
  review is involved, and the bundle identifier `com.statsdirect.viewer.prototype` needs no registration.
- `StatsDirect.entitlements` holds only `com.apple.security.cs.allow-jit`: the hardened runtime otherwise refuses the
  CoreCLR just-in-time compiler. Library validation stays on, which a Developer ID signature satisfies because every
  library in the bundle then carries the team identifier.
- `RConsoleWorker.entitlements` applies only to the separate R helper. It allows JIT and disables library validation
  so the helper can load the user's external `libR.dylib` and native CRAN packages signed by other organisations.
  The worker does not receive unsigned-executable-memory, debugger or Apple-events permissions. The main app and
  other bundled code keep their existing policy. After signing, test a real R command and an SVG chart as well as
  verifying signatures; an ad hoc test cannot by itself certify Developer ID or notarisation behaviour.
- The timestamp and the stapled ticket let the app open on a Mac that is offline.
