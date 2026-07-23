"""파인튜닝된 감정 분류기의 test 평가와 UI 노출 판정.

산출:
- eval_report.json / eval_report.md (run 디렉터리 아래)
- confusion_matrix.csv
- macro-F1, 클래스별 precision/recall, ECE, Brier score
- confidence/entropy 기준 abstain(uncertain) 비율 스윕

판정 규칙(설계서 6.1): 다수 클래스 예측과 TF-IDF+LR 베이스라인을 모두
이기지 못하거나, 사실상 동작하지 않는 클래스(F1이 기준 미만)가 있으면
ui_exposure_allowed=false로 기록하고 앱에는 AI 라벨을 노출하지 않는다.

실행 예:
  python evaluate.py --run-id 20260712_020101_seed42 --data-version aihub-v1.2
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
import torch
from sklearn.metrics import classification_report, confusion_matrix, f1_score
from transformers import AutoModelForSequenceClassification, AutoTokenizer

import label_mapping
from common import model_root, processed_data_dir

# 이 값 미만의 F1인 클래스는 "사실상 동작하지 않음"으로 본다.
DEAD_CLASS_F1 = 0.10

CONFIDENCE_THRESHOLDS = [round(0.50 + 0.05 * i, 2) for i in range(10)]  # 0.50~0.95
ENTROPY_THRESHOLDS = [0.4, 0.6, 0.8, 1.0, 1.2, 1.4]


def predict_proba(model_dir: Path, texts: list[str], batch_size: int, max_length: int) -> np.ndarray:
    device = "cuda" if torch.cuda.is_available() else "cpu"
    tokenizer = AutoTokenizer.from_pretrained(model_dir)
    model = AutoModelForSequenceClassification.from_pretrained(model_dir).to(device).eval()
    probs = []
    with torch.no_grad():
        for i in range(0, len(texts), batch_size):
            enc = tokenizer(
                texts[i : i + batch_size],
                truncation=True,
                max_length=max_length,
                padding=True,
                return_tensors="pt",
            ).to(device)
            logits = model(**enc).logits
            probs.append(torch.softmax(logits, dim=-1).cpu().numpy())
    return np.concatenate(probs)


def expected_calibration_error(probs: np.ndarray, labels: np.ndarray, n_bins: int = 15) -> float:
    conf = probs.max(axis=1)
    pred = probs.argmax(axis=1)
    correct = (pred == labels).astype(float)
    bins = np.linspace(0.0, 1.0, n_bins + 1)
    ece = 0.0
    for lo, hi in zip(bins[:-1], bins[1:]):
        mask = (conf > lo) & (conf <= hi)
        if mask.any():
            ece += mask.mean() * abs(correct[mask].mean() - conf[mask].mean())
    return float(ece)


def brier_score(probs: np.ndarray, labels: np.ndarray) -> float:
    onehot = np.eye(probs.shape[1])[labels]
    return float(np.mean(np.sum((probs - onehot) ** 2, axis=1)))


def abstain_sweep(probs: np.ndarray, labels: np.ndarray) -> dict:
    """확신도가 낮은 예측을 uncertain으로 보류했을 때의 커버리지-성능 곡선."""
    pred = probs.argmax(axis=1)
    conf = probs.max(axis=1)
    entropy = -np.sum(probs * np.log(np.clip(probs, 1e-12, 1.0)), axis=1)

    def row(mask: np.ndarray) -> dict:
        covered = mask.mean()
        macro = (
            f1_score(labels[mask], pred[mask], average="macro", zero_division=0)
            if mask.any()
            else None
        )
        return {
            "uncertain_ratio": round(float(1.0 - covered), 4),
            "covered_macro_f1": None if macro is None else round(float(macro), 4),
        }

    return {
        "confidence": {str(t): row(conf >= t) for t in CONFIDENCE_THRESHOLDS},
        "entropy": {str(t): row(entropy <= t) for t in ENTROPY_THRESHOLDS},
    }


def build_markdown(report: dict) -> str:
    v = report["verdict"]
    lines = [
        f"# 감정 분류기 평가 리포트 — {report['run_id']}",
        "",
        f"- 생성 시각: {report['created_at']}",
        f"- 데이터 버전: {report['data_version']} / 매핑 버전: {report['mapping_version']}",
        f"- test 크기: {report['test_size']}",
        "",
        "## 판정",
        "",
        f"- **UI 노출 허용: {'예' if v['ui_exposure_allowed'] else '아니오'}**",
        *[f"- {reason}" for reason in v["reasons"]],
        "",
        "## 핵심 지표",
        "",
        f"- macro-F1: {report['metrics']['macro_f1']:.4f}",
        f"- 다수 클래스 macro-F1: {report['baselines']['majority_macro_f1']}",
        f"- TF-IDF+LR macro-F1: {report['baselines']['tfidf_lr_macro_f1']}",
        f"- ECE: {report['metrics']['ece']:.4f} / Brier: {report['metrics']['brier']:.4f}",
        "",
        "## 클래스별 성능",
        "",
        "| 클래스 | precision | recall | F1 | support |",
        "|--------|-----------|--------|----|---------|",
    ]
    for label, m in report["metrics"]["per_class"].items():
        lines.append(
            f"| {label} | {m['precision']:.3f} | {m['recall']:.3f} | {m['f1']:.3f} | {int(m['support'])} |"
        )
    lines += [
        "",
        "## abstain 스윕 (confidence 기준)",
        "",
        "| threshold | uncertain 비율 | 커버 구간 macro-F1 |",
        "|-----------|----------------|--------------------|",
    ]
    for t, r in report["abstain_sweep"]["confidence"].items():
        lines.append(f"| {t} | {r['uncertain_ratio']} | {r['covered_macro_f1']} |")
    lines += ["", "confusion matrix는 confusion_matrix.csv 참고.", ""]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", required=True, help="train.py가 만든 run 디렉터리 이름")
    parser.add_argument("--data-version", default="aihub-v1.2")
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--max-length", type=int, default=256)
    args = parser.parse_args()

    run_dir = model_root() / "emotion_classifier" / args.run_id
    model_dir = run_dir / "model"
    if not model_dir.is_dir():
        raise SystemExit(f"{model_dir} 가 없습니다. train.py를 먼저 실행하세요.")

    test_path = processed_data_dir(args.data_version) / "test.parquet"
    if not test_path.is_file():
        raise SystemExit(f"{test_path} 가 없습니다. prepare_data.py를 먼저 실행하세요.")
    test = pd.read_parquet(test_path)

    probs = predict_proba(model_dir, test["text"].tolist(), args.batch_size, args.max_length)
    labels = test["label_id"].to_numpy()
    preds = probs.argmax(axis=1)
    pred_names = [label_mapping.ID2LABEL[int(p)] for p in preds]

    cls_report = classification_report(
        test["label"], pred_names, labels=list(label_mapping.MAJOR_LABELS),
        output_dict=True, zero_division=0,
    )
    per_class = {
        label: {
            "precision": float(cls_report[label]["precision"]),
            "recall": float(cls_report[label]["recall"]),
            "f1": float(cls_report[label]["f1-score"]),
            "support": int(cls_report[label]["support"]),
        }
        for label in label_mapping.MAJOR_LABELS
    }
    macro_f1 = float(f1_score(labels, preds, average="macro", zero_division=0))

    cm = confusion_matrix(labels, preds, labels=list(range(len(label_mapping.MAJOR_LABELS))))
    cm_df = pd.DataFrame(
        cm,
        index=[f"true_{name}" for name in label_mapping.MAJOR_LABELS],
        columns=[f"pred_{name}" for name in label_mapping.MAJOR_LABELS],
    )
    cm_df.to_csv(run_dir / "confusion_matrix.csv", encoding="utf-8-sig")

    # 베이스라인 리포트가 있으면 비교 판정에 사용한다.
    baseline_path = model_root() / "emotion_classifier" / "baseline_tfidf" / "baseline_report.json"
    tfidf_f1 = majority_f1 = None
    if baseline_path.is_file():
        baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
        tfidf_f1 = baseline["tfidf_lr"]["macro_f1"]
        majority_f1 = baseline["majority_class"]["macro_f1"]

    reasons = []
    allowed = True
    if tfidf_f1 is None:
        allowed = False
        reasons.append("baseline_tfidf.py 리포트가 없어 베이스라인 비교를 하지 못함")
    else:
        if macro_f1 <= majority_f1:
            allowed = False
            reasons.append(f"다수 클래스 예측(macro-F1 {majority_f1:.4f})을 이기지 못함")
        if macro_f1 <= tfidf_f1:
            allowed = False
            reasons.append(f"TF-IDF+LR 베이스라인(macro-F1 {tfidf_f1:.4f})을 이기지 못함")
    dead = [name for name, m in per_class.items() if m["f1"] < DEAD_CLASS_F1]
    if dead:
        allowed = False
        reasons.append(f"사실상 동작하지 않는 클래스 존재 (F1<{DEAD_CLASS_F1}): {', '.join(dead)}")
    if not label_mapping.PREFIX_MAPPING_VERIFIED:
        allowed = False
        reasons.append("라벨 매핑이 원본 라벨표와 아직 대조되지 않음 (README 검증 절차 필요)")
    if allowed:
        reasons.append("모든 판정 기준 통과")

    report = {
        "run_id": args.run_id,
        "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "data_version": args.data_version,
        "mapping_version": label_mapping.MAPPING_VERSION,
        "test_size": len(test),
        "metrics": {
            "macro_f1": macro_f1,
            "per_class": per_class,
            "ece": expected_calibration_error(probs, labels),
            "brier": brier_score(probs, labels),
        },
        "baselines": {
            "majority_macro_f1": majority_f1,
            "tfidf_lr_macro_f1": tfidf_f1,
        },
        "abstain_sweep": abstain_sweep(probs, labels),
        "verdict": {"ui_exposure_allowed": allowed, "reasons": reasons},
    }
    (run_dir / "eval_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (run_dir / "eval_report.md").write_text(build_markdown(report), encoding="utf-8")

    print(f"macro-F1: {macro_f1:.4f} / ECE: {report['metrics']['ece']:.4f}")
    print(f"UI 노출 허용: {allowed}")
    for reason in reasons:
        print(f"  - {reason}")
    print(f"리포트 저장: {run_dir / 'eval_report.md'}")


if __name__ == "__main__":
    main()
