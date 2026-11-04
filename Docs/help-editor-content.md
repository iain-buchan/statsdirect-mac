# Help Editor content in Mac builds

The Help Editor publishes the website, desktop help and tutor library together
in one revision of `https://github.com/iain-buchan/statisticalhelp`:

- `Docs` supplies the website.
- `Published/DesktopHelp` supplies the offline Mac help reader.
- `Published/Tutor` supplies the built-in lessons, questions and pathways.
- `Published/content-manifest.json` identifies the publication and its file hashes.

This content revision is independent of `FullEngine/Upstream`. Refreshing help
and teaching material does not update the calculation engine. Installed apps
read the content bundled into their application; they do not fetch replacement
help or tutor content at runtime.

The first committed shared snapshot is
[`bfe33836ec8bd6b5a211a530c5b248d8ee6c9340`](https://github.com/iain-buchan/statisticalhelp/commit/bfe33836ec8bd6b5a211a530c5b248d8ee6c9340),
produced by Help Editor code `09f032011d4058b4beb75700976c1a84a9c3c528`.
It contains 404 help topics, 403 search documents and 404 context mappings,
plus 12 lessons, 35 questions and five pathways. Its 47 existing editorial
warnings are retained; importing it does not imply expert approval. Later
latest-mode builds resolve later complete publications without changing the
engine pin.

## App build modes

`./build.sh` defaults to `STATSDIRECT_CONTENT_MODE=latest`. Before compilation,
`Scripts/prepare-content-build.py` fetches the official content repository into
the controlled `.build/statisticalhelp.git` cache and resolves the latest
publication to one full commit. Both consumers use that same commit and verify
the shared manifest, producer receipts, schemas and complete file inventories.
It stages both imports before activating them, regenerates the Learning bundle
and captures an immutable content snapshot for the rest of the app build.

A network or validation failure stops the build. It does not silently reuse an
older publication. Local changes to previously imported source are preserved:
the importer refuses to overwrite an edited or partial imported bundle.

Use the committed, validated inputs without a content fetch:

```sh
STATSDIRECT_CONTENT_MODE=offline ./build.sh
```

Use a particular publication already present in the local Git cache:

```sh
STATSDIRECT_CONTENT_MODE=pinned \
STATSDIRECT_CONTENT_REVISION=<full-40-character-publication-commit> ./build.sh
```

Pinned mode does not fetch a missing revision. Fetch that exact commit into the
controlled cache first, or run the latest mode once. The optional
`STATSDIRECT_CONTENT_REPOSITORY` names another local cache of the same official
repository. CI explicitly uses offline mode so a later content publication
cannot change an already committed CI input.

`content-build-input.json` records the mode, resolved revision and publication
hash under the build work directory and in the built app's Resources folder.
The copied help and learning provenance manifests retain the publisher's exact
receipts and hashes. Git attributes preserve their original bytes, including
Windows line endings.

## Explicit refresh and validation

To refresh the committed copies without building an application:

```sh
python3 Scripts/prepare-content-build.py --mode latest
```

The individual `import-desktop-help.py` and `import-authored-tutor.py` commands
also accept an explicit full revision and local `--repository`. Their default
sources are `Published/DesktopHelp` and `Published/Tutor`. Explicit legacy
Windows source paths remain supported for compatibility tests. The normal
build's joint guard rejects mixed publication revisions.

To check the committed content without Git or a network connection:

```sh
python3 Scripts/check-content-imports.py
```

Incomplete-import markers block verification and building. If an import was
interrupted, inspect the recorded transaction and its retained backups before
restoring or completing it; a partially activated tree is not accepted.

## Learner and review metadata

The tutor consumer preserves the producer's lesson/question/pathway IDs and
complete JSON records. It reads the published JSON rather than executing the
publisher's generated `bank.mjs`. Question snapshots, old attempt order and
learner portfolios keep their existing identities. No learner files are
part of a content import.

Difficulty, learner goals, review status and review content hashes survive
import, practice snapshots and native tutor context. The publication declares
`authoring-source-before-generated-sync-v1` review binding: its review proofs
refer to the saved authoring records before the publisher synchronises question
mirrors and content versions. These proofs are preserved rather than compared
incorrectly to transformed output. Published payload hashes and embedded/flat
question coherence are checked separately. Explicit published-record proofs
use the producer's canonical UTF-16 ordering, escaping and numeric tokens.
Review metadata is displayed as supplied; publication is not relabelled as
human review or accreditation. Existing draft warnings remain in provenance.

Focused checks cover malformed/partial publications, hashes, IDs, review
metadata, progress restoration, transactional replacement, offline/pinned
behaviour and both help-reader formats. The native `content` CI suite builds
the ordinary application and exercises help and Learning without producing an
installer or running the full unrelated engine/UI suite.
