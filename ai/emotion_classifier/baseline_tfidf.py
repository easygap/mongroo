"""TF-IDF + Logistic Regression 베이스라인.

KcELECTRA 파인튜닝이 이 선형 베이스라인과 다수 클래스 예측을 이기지 못하면
AI 라벨을 UI에 노출하지 않는다(설계서 6.1). evaluate.py가 이 스크립트의
리포트를 읽어 비교 판정을 내린다.

실행 예:
  python baseline_tfidf.py --data-version aihub-v1.2 --seed 42
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone

import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import classification_report, f1_score
from sklearn.pipeline import Pipeline

import label_mapping
from common import model_root, processed_data_dir, set_seed


def load_split(data_version: str, name: str) -> pd.DataFrame:
    path = processed_data_dir(data_version) / f"{name}.parquet"
    if not path.is_file():
        raise SystemExit(f"{path} 가 없습니다. prepare_data.py를 먼저 실행하세요.")
    return pd.read_parquet(path)


def evaluate_predictions(y_true, y_pred) -> dict:
    report = classification_report(
        y_true, y_pred, labels=list(label_mapping.MAJOR_LABELS), output_dict=True, zero_division=0
    )
    # sklearn이 numpy 스칼라를 돌려주므로 JSON 직렬화 전에 기본형으로 바꾼다.
    return {
        "macro_f1": float(f1_score(y_true, y_pred, average="macro", zero_division=0)),
        "per_class": {
            label: {
                "precision": float(report[label]["precision"]),
                "recall": float(report[label]["recall"]),
                "f1": float(report[label]["f1-score"]),
                "support": int(report[label]["support"]),
            }
            for label in label_mapping.MAJOR_LABELS
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-version", default="aihub-v1.2")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--max-features", type=int, default=100_000)
    args = parser.parse_args()
    set_seed(args.seed)

    train = load_split(args.data_version, "train")
    test = load_split(args.data_version, "test")

    # 한국어 교착어 특성상 word n-gram만으로는 어미 변화를 놓치기 쉬워
    # char 3~5gram을 함께 쓴다.
    pipeline = Pipeline(
        [
            (
                "tfidf",
                TfidfVectorizer(
                    analyzer="char_wb",
                    ngram_range=(2, 5),
                    max_features=args.max_features,
                    sublinear_tf=True,
                ),
            ),
            (
                "clf",
                LogisticRegression(
                    max_iter=2000, class_weight="balanced", random_state=args.seed
                ),
            ),
        ]
    )
    pipeline.fit(train["text"], train["label"])
    pred = pipeline.predict(test["text"])

    metrics = evaluate_predictions(test["label"], pred)

    # 다수 클래스 예측 기준선도 같이 남긴다.
    majority = train["label"].value_counts().idxmax()
    majority_metrics = evaluate_predictions(test["label"], [majority] * len(test))

    out_dir = model_root() / "emotion_classifier" / "baseline_tfidf"
    out_dir.mkdir(parents=True, exist_ok=True)
    report = {
        "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "data_version": args.data_version,
        "mapping_version": label_mapping.MAPPING_VERSION,
        "seed": args.seed,
        "vectorizer": f"char_wb 2-5gram, max_features={args.max_features}",
        "model": "LogisticRegression(class_weight=balanced)",
        "test_size": len(test),
        "tfidf_lr": metrics,
        "majority_class": {"label": majority, **majority_metrics},
    }
    out_path = out_dir / "baseline_report.json"
    out_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"TF-IDF+LR macro-F1: {metrics['macro_f1']:.4f}")
    print(f"다수 클래스({majority}) macro-F1: {majority_metrics['macro_f1']:.4f}")
    for label, m in metrics["per_class"].items():
        print(f"  {label}: P={m['precision']:.3f} R={m['recall']:.3f} F1={m['f1']:.3f}")
    print(f"리포트 저장: {out_path}")


if __name__ == "__main__":
    main()
