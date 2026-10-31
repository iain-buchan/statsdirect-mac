# Signing and notarising a StatsDirect for Mac release

A release is built and tested here first, then signed and notarised by someone holding the University of Liverpool's
Apple Developer ID, and published. Nothing in this repository or its workflows holds a certificate or a password.

## Release policy

- Only a Developer ID signed, notarised, stapled and verified build may become GitHub's **Latest** stable release,
  be offered through **Help → Check for Updates**, or replace the public download linked from
  [StatsDirect downloads](https://www.statsdirect.com/download.aspx).
- Until then, keep the candidate in a **draft** for the signing handover, or publish it explicitly as a
  **pre-release** with `make_latest: false` for testing. Never publish an unsigned candidate as a stable release,
  overwrite the live release's assets, or replace the stable `StatsDirect-macOS-arm64.zip` alias with it.
- As agreed on 31 October 2026, **1.0.0 remains the live signed and notarised release**. The University signs and
  notarises once a week; the next planned handover for **1.0.1 is Wednesday, 4 November 2026**. The date alone does
  not authorise promotion: wait for the returned build and verify it first.
- StatsDirect Ltd's separate Apple Developer enrolment is pending. Continue using the University's signing route
  until the company's Developer ID certificate, private key and notarisation access are active and verified.
  When switching, use the company's actual signing identity and its own notarytool profile; record the signer
  and team in `BUILD-INFO.txt`.

## What you need

- An Apple Silicon Mac with macOS 14 or later and the Xcode command line tools (`xcode-select --install`), which
  provide `codesign`, `xcrun notarytool` and `xcrun stapler`.
- The **Developer ID Application** certificate of the University's Apple Developer account, with its private key, in
  your login keychain. `security find-identity -v -p codesigning` must list it as valid, for example
  `Developer ID Application: University of Liverpool (ULCPE837C7)`. Use the identity exactly as that line prints it.
- A notarytool keychain profile, made once from an Apple ID that is a member of the team, with an app-specific password
  from account.apple.com (not the Apple ID password), or from an App Store Connect API key:

  ```sh
  xcrun notarytool store-credentials StatsDirect-notary --apple-id you@liverpool.ac.uk --team-id ULCPE837C7
  # or
  xcrun notarytool store-credentials StatsDirect-notary --key AuthKey_XXXXXXXX.p8 --key-id XXXXXXXX --issuer <issuer id>
  ```

- A clone of this repository at the release tag, for `Scripts/sign-app.sh` and `StatsDirect.entitlements`:

  ```sh
  git clone https://github.com/iain-buchan/statsdirect-mac.git
  cd statsdirect-mac && git checkout v1.0.0
  ```

## Steps

1. From the draft or explicitly marked pre-release candidate on GitHub, download `StatsDirect-<version>-macOS-arm64-unsigned.zip` and `SHA256SUMS.txt`,
   and check the hash before touching anything: `shasum -a 256 -c SHA256SUMS.txt --ignore-missing`.
2. Expand it so that resource forks and permissions survive: `ditto -x -k StatsDirect-<version>-macOS-arm64-unsigned.zip .`
   gives `StatsDirect.app` beside the ZIP.
3. Sign every Mach-O inside the bundle and then the bundle, with the hardened runtime, the entitlements and a secure
   timestamp, submit to Apple, wait for the verdict, staple the ticket and validate it, in one command:

   ```sh
   Scripts/sign-app.sh "$PWD/StatsDirect.app" "Developer ID Application: University of Liverpool (ULCPE837C7)" --notarize StatsDirect-notary
   ```

   The script signs the .NET runtime's libraries under `Contents/Resources/Engine` as well as the app's own code (a plain
   `codesign --deep` would miss them), verifies the signature strictly, checks that the `com.apple.security.cs.allow-jit`
   entitlement is in it (the engine runs on CoreCLR and needs nothing else), and ends with `spctl --assess` accepting the
   app. If Apple's verdict is "Invalid", `xcrun notarytool log <submission id> --keychain-profile StatsDirect-notary`
   names the file at fault.
4. Check what you will ship:

   ```sh
   codesign --verify --deep --strict --verbose=2 StatsDirect.app
   spctl --assess --type exec --verbose=2 StatsDirect.app      # "accepted", source=Notarized Developer ID
   xcrun stapler validate StatsDirect.app
   open StatsDirect.app                                        # it launches, Help → About shows the version
   ```

5. Package the signed app and record its hash:

   ```sh
   ditto -c -k --keepParent StatsDirect.app StatsDirect-<version>-macOS-arm64.zip
   shasum -a 256 StatsDirect-<version>-macOS-arm64.zip
   ```

6. On the draft or pre-release candidate: upload `StatsDirect-<version>-macOS-arm64.zip`, remove the `-unsigned` ZIP, replace the line
   for it in `SHA256SUMS.txt` with the signed ZIP's hash, and amend `BUILD-INFO.txt` to say the build is Developer ID
   signed, notarised and stapled, by whom and on which date. Leave the symbols ZIP as it is: the signed app's code is
   the same build, so its symbols still match.
7. After the returned signed build passes step 4, publish the candidate as a stable release and explicitly mark it
   **Latest**. Only then update the public download link or its `StatsDirect-macOS-arm64.zip` alias to the verified
   signed and notarised ZIP. **Help → Check for Updates** in earlier installations then offers it: the updater uses
   GitHub's latest stable release and excludes drafts and pre-releases. Keep the previous release's assets intact.

## Why these choices

- The app is signed for distribution outside the App Store (Developer ID), so no provisioning profile or App Store
  review is involved, and the bundle identifier `com.statsdirect.viewer.prototype` needs no registration.
- `StatsDirect.entitlements` holds only `com.apple.security.cs.allow-jit`: the hardened runtime otherwise refuses the
  CoreCLR just-in-time compiler. Library validation stays on, which a Developer ID signature satisfies because every
  library in the bundle then carries the team identifier.
- The timestamp and the stapled ticket let the app open on a Mac that is offline.
