"""Shared discovery for optional R comparison tests, independent of installation layout."""
import os,shutil
from pathlib import Path

def rscript():
    candidates=[os.environ.get('RSCRIPT'),shutil.which('Rscript'),'/Library/Frameworks/R.framework/Resources/bin/Rscript','/opt/homebrew/bin/Rscript','/usr/local/bin/Rscript']
    for candidate in candidates:
        if candidate and Path(candidate).is_file() and os.access(candidate,os.X_OK): return candidate
    raise SystemExit('R comparison tests need Rscript. Install R, add it to PATH, or set RSCRIPT. Building the application does not require R.')
