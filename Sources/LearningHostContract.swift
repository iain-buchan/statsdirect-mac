// The Learning host contract this build implements (Learn/HOST-CONTRACT.md in the shared package).
// Learn/import_upstream.py checks it against the package's host-contract.json at build; the Learning
// ready handler is to check it at load and answer loadError on a mismatch.
enum LearningHostContract { static let version = 1 }
