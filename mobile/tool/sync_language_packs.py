"""Copy content/language-packs/*.json into mobile/assets/lang/ and write index.json.

The pack files live once, at the repo root, and are shared with the backend.
This runs as part of tool/bootstrap.sh; assets/lang/ is generated (git-ignored).
"""

import json
import shutil
from pathlib import Path

MOBILE = Path(__file__).resolve().parent.parent
SOURCE = MOBILE.parent / "content" / "language-packs"
TARGET = MOBILE / "assets" / "lang"


def main() -> None:
    packs = sorted(SOURCE.glob("*.json"))
    if not any(p.stem == "en" for p in packs):
        raise SystemExit(f"no en.json in {SOURCE}")
    if TARGET.exists():
        shutil.rmtree(TARGET)
    TARGET.mkdir(parents=True)
    for path in packs:
        json.loads(path.read_text(encoding="utf-8"))  # fail early on a broken file
        shutil.copyfile(path, TARGET / path.name)
    (TARGET / "index.json").write_text(json.dumps([p.stem for p in packs]), encoding="utf-8")
    print(f"bundled {len(packs)} language packs: {', '.join(p.stem for p in packs)}")


if __name__ == "__main__":
    main()
