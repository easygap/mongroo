"""파이프라인 스크립트 공용 헬퍼.

데이터/모델 경로는 저장소 밖 환경변수로만 받는다.
- AIHUB_DATA_ROOT: AI Hub 원본 데이터 루트 (재배포 금지 자료)
- MONGROO_MODEL_ROOT: 학습 산출물(가중치, 리포트) 루트
"""

from __future__ import annotations

import hashlib
import os
import sys
from pathlib import Path

# 전처리 로직에 영향을 주는 파일들. 이 목록의 내용 해시가 전처리 코드 SHA가 된다.
_PREPROCESS_SOURCES = ("label_mapping.py", "prepare_data.py")


def require_env_dir(name: str, must_exist: bool = True) -> Path:
    """환경변수로 지정된 디렉터리를 돌려주고, 없으면 한국어 안내 후 종료한다."""
    value = os.environ.get(name, "").strip()
    if not value:
        sys.exit(
            f"환경변수 {name}이(가) 설정되지 않았습니다.\n"
            f"데이터와 모델 가중치는 저장소 밖에 둡니다. 예) PowerShell:\n"
            f'  $env:{name} = "D:\\mongroo\\{name.lower()}"'
        )
    path = Path(value)
    if must_exist and not path.is_dir():
        sys.exit(f"{name}={path} 경로가 존재하지 않습니다. 디렉터리를 먼저 준비하세요.")
    return path


def aihub_data_root() -> Path:
    return require_env_dir("AIHUB_DATA_ROOT")


def model_root() -> Path:
    root = require_env_dir("MONGROO_MODEL_ROOT", must_exist=False)
    root.mkdir(parents=True, exist_ok=True)
    return root


def processed_data_dir(data_version: str) -> Path:
    """전처리 산출물 위치. ai/data/는 .gitignore로 커밋이 차단되어 있다."""
    return Path(__file__).resolve().parent.parent / "data" / "processed" / "emotion" / data_version


def preprocess_code_sha() -> str:
    """전처리 코드(라벨 매핑 포함)의 SHA-256. 산출물 메타와 model card에 기록한다."""
    here = Path(__file__).resolve().parent
    h = hashlib.sha256()
    for name in _PREPROCESS_SOURCES:
        h.update(name.encode("utf-8"))
        h.update((here / name).read_bytes())
    return h.hexdigest()


def set_seed(seed: int) -> None:
    import random

    import numpy as np

    random.seed(seed)
    np.random.seed(seed)
    try:
        import torch

        torch.manual_seed(seed)
        torch.cuda.manual_seed_all(seed)
    except ImportError:
        pass
