"""OpenAPI 스펙을 파일로 내보낸다. CI에서 커밋본과의 drift를 검사한다."""
import json
from pathlib import Path

from app.main import app

if __name__ == "__main__":
    spec = app.openapi()
    out = Path(__file__).resolve().parent.parent / "openapi.json"
    out.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"exported: {out}")
