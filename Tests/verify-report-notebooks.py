#!/usr/bin/env python3
"""Validate actual native exports with Jupyter's schema and execute their R replay."""
import base64
import json
from pathlib import Path
import shutil
import subprocess
import sys

import nbformat

root = Path(sys.argv[1]).resolve()
for name in ("review-notebook.ipynb", "moved-notebook.ipynb"):
    book = json.loads((root / name).read_text())
    ids = [c.get("id") for c in book["cells"]]
    assert all(ids) and len(ids) == len(set(ids)), "missing or duplicate cell ids"
    nbformat.validate(book, version=4, version_minor=5)
    assert book["metadata"]["kernelspec"] == {"name": "ir", "display_name": "R", "language": "R"}
    assert book["metadata"]["language_info"]["name"] == "R"
    original = book["metadata"]["statsdirect"]
    assert original["reportHtml"] and original["entries"]
    for cell in book["cells"]:
        if cell["cell_type"] == "code":
            assert cell["execution_count"] is None and cell["outputs"] == []
        for bundle in cell.get("attachments", {}).values():
            assert "image/png" in bundle
            png = base64.b64decode(bundle["image/png"], validate=True)
            assert png.startswith(b"\x89PNG\r\n\x1a\n")
            if "image/svg+xml" in bundle:
                assert "<svg" in bundle["image/svg+xml"]
    print(f"PASS: Jupyter 4.5 schema, R kernel, unexecuted cells and portable attachments: {name}")

book = json.loads((root / "review-notebook.ipynb").read_text())
assert book["metadata"]["statsdirect"]["entries"][3]["record"]["values"]["precisionProbe"] == 9007199254740993
code = []
for cell in book["cells"]:
    if cell["cell_type"] == "code":
        source = cell["source"]
        code.append(source if isinstance(source, str) else "".join(source))
assert any("local({" in source and "t.test(" in source for source in code)
rscript = shutil.which("Rscript") or "/usr/local/bin/Rscript"
target = root / "notebook-replay.R"
pdf = json.dumps(str(root / "notebook-replay.pdf"))
target.write_text("pdf(" + pdf + ")\n" + "\n\n".join(code) +
                  "\nstopifnot(!exists('before',envir=.GlobalEnv,inherits=FALSE),"
                  "!exists('after',envir=.GlobalEnv,inherits=FALSE))\n"
                  "dev.off()\ncat('NOTEBOOK_REPLAY_OK\\n')\n")
run = subprocess.run([rscript, "--vanilla", str(target)], text=True, capture_output=True, timeout=90)
(root / "notebook-replay.log").write_text(run.stdout + run.stderr)
assert run.returncode == 0 and "NOTEBOOK_REPLAY_OK" in run.stdout, run.stdout + run.stderr
assert (root / "notebook-replay.pdf").stat().st_size > 1000
print("PASS: exported notebook R cells execute, draw their plots and leave each analysis isolated")
