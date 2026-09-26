"""Publish the canonical lesson catalogue; never reconstruct older teaching text."""
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
source = root / "Learn/lessons.json"
lessons = json.loads(source.read_text())
assert len({lesson["id"] for lesson in lessons}) == len(lessons)
(root / "Content/Learn/lessons.json").write_text(
    json.dumps(lessons, ensure_ascii=False, indent=2) + "\n"
)
