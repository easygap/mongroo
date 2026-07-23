"""AI Hub 감성 대화 말뭉치 원본을 학습용 parquet으로 정규화한다.

입력: AIHUB_DATA_ROOT 아래의 원본 JSON/xlsx (저장소 밖 보관, 재배포 금지)
출력: ai/data/processed/emotion/{data_version}/ 아래
      train.parquet / val.parquet / test.parquet / meta.json

문장 무작위 분할 대신 화자(profile-id) 단위 GroupShuffleSplit을 써서
같은 화자의 발화가 train과 test에 동시에 들어가는 누수를 막는다.

실행 예:
  python prepare_data.py --data-version aihub-v1.2 --seed 42
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
from sklearn.model_selection import GroupShuffleSplit

import label_mapping
from common import aihub_data_root, preprocess_code_sha, processed_data_dir

# 배포본에 따라 키 이름이 다를 수 있어 후보를 순서대로 시도한다.
_EMOTION_KEY_PATHS = (
    ("profile", "emotion", "type"),
    ("profile", "emotion", "emotion-id"),
    ("emotion", "type"),
    ("emotion", "emotion-id"),
)
_GROUP_KEY_PATHS = (
    ("talk", "id", "profile-id"),
    ("profile", "persona-id"),
    ("profile", "persona", "persona-id"),
    ("talk", "id", "talk-id"),
)
# xlsx 배포본의 컬럼 후보
_XLSX_EMOTION_COLS = ("감정_소분류", "감정_대분류", "유형", "emotion")
_XLSX_TEXT_PREFIX = "사람문장"


def _dig(record: dict, path: tuple[str, ...]):
    cur = record
    for key in path:
        if not isinstance(cur, dict) or key not in cur:
            return None
        cur = cur[key]
    return cur


def _human_turns(record: dict) -> str:
    """talk.content에서 사람 발화(HS*)만 순서대로 이어붙인다."""
    content = _dig(record, ("talk", "content"))
    if not isinstance(content, dict):
        return ""
    turns = [
        str(v).strip()
        for k, v in sorted(content.items())
        if k.upper().startswith("HS") and str(v).strip()
    ]
    return " ".join(turns)


def _iter_json_records(path: Path):
    with path.open(encoding="utf-8") as f:
        data = json.load(f)
    if isinstance(data, list):
        yield from data
    elif isinstance(data, dict):
        # 리스트를 값으로 갖는 최상위 키가 있으면 그것을 본문으로 본다.
        for value in data.values():
            if isinstance(value, list):
                yield from value
                return
        yield data


def _extract_from_json(path: Path, stats: Counter) -> list[dict]:
    rows = []
    for i, record in enumerate(_iter_json_records(path)):
        if not isinstance(record, dict):
            stats["skip_not_dict"] += 1
            continue
        raw_emotion = next(
            (v for p in _EMOTION_KEY_PATHS if (v := _dig(record, p)) is not None), None
        )
        if raw_emotion is None:
            stats["skip_no_emotion_key"] += 1
            continue
        text = _human_turns(record)
        if not text:
            stats["skip_no_text"] += 1
            continue
        group = next(
            (v for p in _GROUP_KEY_PATHS if (v := _dig(record, p)) is not None), None
        )
        if group is None:
            group = f"{path.name}#{i}"
            stats["fallback_group_id"] += 1
        try:
            label = label_mapping.map_label(str(raw_emotion))
        except label_mapping.UnknownEmotionLabelError:
            stats["skip_unknown_label"] += 1
            continue
        rows.append(
            {"text": text, "label": label, "group_id": str(group), "source_file": path.name}
        )
    return rows


def _extract_from_xlsx(path: Path, stats: Counter) -> list[dict]:
    df = pd.read_excel(path)
    emotion_col = next((c for c in _XLSX_EMOTION_COLS if c in df.columns), None)
    text_cols = [c for c in df.columns if str(c).startswith(_XLSX_TEXT_PREFIX)]
    if emotion_col is None or not text_cols:
        stats["skip_xlsx_schema"] += 1
        print(f"  컬럼 인식 실패로 건너뜀: {path.name} (columns={list(df.columns)[:12]})")
        return []
    rows = []
    for i, row in df.iterrows():
        text = " ".join(
            str(row[c]).strip() for c in text_cols if pd.notna(row[c]) and str(row[c]).strip()
        )
        if not text:
            stats["skip_no_text"] += 1
            continue
        try:
            label = label_mapping.map_label(str(row[emotion_col]))
        except label_mapping.UnknownEmotionLabelError:
            stats["skip_unknown_label"] += 1
            continue
        # xlsx 배포본에는 화자 ID가 없어 행 단위 그룹으로 둔다. 대화 누수 방지 효과는
        # JSON 배포본만 못하므로 가능하면 JSON 원본을 쓴다.
        rows.append(
            {"text": text, "label": label, "group_id": f"{path.name}#{i}", "source_file": path.name}
        )
    if rows:
        stats["fallback_group_id"] += len(rows)
    return rows


def load_raw(root: Path) -> tuple[pd.DataFrame, Counter]:
    stats: Counter = Counter()
    rows: list[dict] = []
    files = sorted([*root.rglob("*.json"), *root.rglob("*.xlsx")])
    if not files:
        sys.exit(f"AIHUB_DATA_ROOT={root} 아래에서 JSON/xlsx 파일을 찾지 못했습니다.")
    for path in files:
        print(f"읽는 중: {path.relative_to(root)}")
        try:
            if path.suffix == ".json":
                rows.extend(_extract_from_json(path, stats))
            else:
                rows.extend(_extract_from_xlsx(path, stats))
        except Exception as exc:  # 원본 파일 하나가 깨져도 전체를 멈추지 않는다
            stats["skip_file_error"] += 1
            print(f"  파일 처리 실패로 건너뜀: {path.name} ({exc})")
    if not rows:
        sys.exit(
            "레코드를 하나도 추출하지 못했습니다. 원본 스키마가 예상과 다를 수 있으니\n"
            "JSON 최상위 구조와 emotion/talk 키 이름을 확인한 뒤 "
            "_EMOTION_KEY_PATHS/_GROUP_KEY_PATHS를 조정하세요."
        )
    df = pd.DataFrame(rows)
    before = len(df)
    df = df.drop_duplicates(subset=["text"]).reset_index(drop=True)
    stats["drop_duplicate_text"] = before - len(df)
    return df, stats


def group_split(
    df: pd.DataFrame, seed: int, val_ratio: float, test_ratio: float
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    groups = df["group_id"]
    splitter = GroupShuffleSplit(n_splits=1, test_size=test_ratio, random_state=seed)
    rest_idx, test_idx = next(splitter.split(df, groups=groups))
    rest, test = df.iloc[rest_idx], df.iloc[test_idx]

    val_size = val_ratio / (1.0 - test_ratio)
    splitter2 = GroupShuffleSplit(n_splits=1, test_size=val_size, random_state=seed)
    train_idx, val_idx = next(splitter2.split(rest, groups=rest["group_id"]))
    train, val = rest.iloc[train_idx], rest.iloc[val_idx]

    overlap = set(train["group_id"]) & (set(val["group_id"]) | set(test["group_id"]))
    assert not overlap, f"그룹 누수 발견: {sorted(overlap)[:5]}"
    return (
        train.reset_index(drop=True),
        val.reset_index(drop=True),
        test.reset_index(drop=True),
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-version", default="aihub-v1.2", help="원본 데이터 버전 태그")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--val-ratio", type=float, default=0.1)
    parser.add_argument("--test-ratio", type=float, default=0.1)
    parser.add_argument("--min-chars", type=int, default=5, help="이보다 짧은 텍스트 제외")
    args = parser.parse_args()

    if not label_mapping.PREFIX_MAPPING_VERIFIED:
        print(
            "[경고] 라벨 매핑이 아직 원본 라벨표와 대조되지 않았습니다"
            f" (MAPPING_VERSION={label_mapping.MAPPING_VERSION}).\n"
            "       README의 라벨 검증 절차를 마치기 전 산출물은 실험용으로만 사용하세요."
        )

    root = aihub_data_root()
    df, stats = load_raw(root)

    short = df["text"].str.len() < args.min_chars
    stats["drop_too_short"] = int(short.sum())
    df = df[~short].reset_index(drop=True)
    df["label_id"] = df["label"].map(label_mapping.LABEL2ID)

    train, val, test = group_split(df, args.seed, args.val_ratio, args.test_ratio)

    out_dir = processed_data_dir(args.data_version)
    out_dir.mkdir(parents=True, exist_ok=True)
    splits = {"train": train, "val": val, "test": test}
    for name, part in splits.items():
        part.to_parquet(out_dir / f"{name}.parquet", index=False)

    meta = {
        "data_version": args.data_version,
        "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "preprocess_code_sha256": preprocess_code_sha(),
        "mapping_version": label_mapping.MAPPING_VERSION,
        "prefix_mapping_verified": label_mapping.PREFIX_MAPPING_VERIFIED,
        "code_prefix_to_major": label_mapping.CODE_PREFIX_TO_MAJOR,
        "seed": args.seed,
        "split_method": "GroupShuffleSplit(group=화자/대화 ID)",
        "ratios": {"val": args.val_ratio, "test": args.test_ratio},
        "min_chars": args.min_chars,
        "counts": {name: len(part) for name, part in splits.items()},
        "label_distribution": {
            name: part["label"].value_counts().to_dict() for name, part in splits.items()
        },
        "group_counts": {name: part["group_id"].nunique() for name, part in splits.items()},
        "skipped": dict(stats),
        "source_files_sha256": {
            p.name: hashlib.sha256(p.read_bytes()).hexdigest()[:16]
            for p in sorted(root.rglob("*.json"))
        },
    }
    (out_dir / "meta.json").write_text(
        json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    print(f"\n저장 완료: {out_dir}")
    for name, part in splits.items():
        print(f"  {name}: {len(part)}건, 그룹 {part['group_id'].nunique()}개")
    print(f"  제외/보정 내역: {dict(stats)}")


if __name__ == "__main__":
    main()
