"""KcELECTRA 감정 분류기 파인튜닝.

- base 모델은 beomi/KcELECTRA-base의 특정 revision을 명시해서 받는다.
- 클래스 불균형은 학습 데이터 빈도의 역수로 가중한 CrossEntropy로 보정한다.
- 산출물은 MONGROO_MODEL_ROOT/emotion_classifier/{run_id}/에 저장하고,
  재현에 필요한 정보(split, seed, 전처리 SHA, 데이터 버전, base revision)를
  model_card.json으로 남긴다.

실행 예:
  python train.py --base-revision <commit-hash> --data-version aihub-v1.2 --fp16
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone

import numpy as np
import pandas as pd
import torch
from datasets import Dataset
from sklearn.metrics import f1_score
from transformers import (
    AutoModelForSequenceClassification,
    AutoTokenizer,
    EarlyStoppingCallback,
    Trainer,
    TrainingArguments,
)

import label_mapping
from common import model_root, preprocess_code_sha, processed_data_dir, set_seed


class WeightedTrainer(Trainer):
    """클래스 가중 CrossEntropy를 쓰는 Trainer."""

    def __init__(self, class_weights: torch.Tensor, **kwargs):
        super().__init__(**kwargs)
        self._class_weights = class_weights

    def compute_loss(self, model, inputs, return_outputs=False, **kwargs):
        labels = inputs.pop("labels")
        outputs = model(**inputs)
        loss_fn = torch.nn.CrossEntropyLoss(
            weight=self._class_weights.to(outputs.logits.device)
        )
        loss = loss_fn(outputs.logits, labels)
        return (loss, outputs) if return_outputs else loss


def load_split(data_version: str, name: str) -> pd.DataFrame:
    path = processed_data_dir(data_version) / f"{name}.parquet"
    if not path.is_file():
        raise SystemExit(f"{path} 가 없습니다. prepare_data.py를 먼저 실행하세요.")
    return pd.read_parquet(path)


def compute_metrics(eval_pred):
    logits, labels = eval_pred
    preds = np.argmax(logits, axis=-1)
    return {"macro_f1": f1_score(labels, preds, average="macro", zero_division=0)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-model", default="beomi/KcELECTRA-base")
    parser.add_argument(
        "--base-revision",
        required=True,
        help="base 모델의 커밋 해시 또는 태그. 재현을 위해 반드시 고정한다.",
    )
    parser.add_argument("--data-version", default="aihub-v1.2")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--max-length", type=int, default=256)
    parser.add_argument("--epochs", type=int, default=3)
    parser.add_argument("--lr", type=float, default=2e-5)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--fp16", action="store_true", help="GPU가 있을 때만 사용")
    args = parser.parse_args()
    set_seed(args.seed)

    train_df = load_split(args.data_version, "train")
    val_df = load_split(args.data_version, "val")
    data_meta = json.loads(
        (processed_data_dir(args.data_version) / "meta.json").read_text(encoding="utf-8")
    )

    tokenizer = AutoTokenizer.from_pretrained(args.base_model, revision=args.base_revision)
    model = AutoModelForSequenceClassification.from_pretrained(
        args.base_model,
        revision=args.base_revision,
        num_labels=len(label_mapping.MAJOR_LABELS),
        id2label=dict(label_mapping.ID2LABEL),
        label2id=label_mapping.LABEL2ID,
    )

    def tokenize(batch):
        return tokenizer(batch["text"], truncation=True, max_length=args.max_length)

    train_ds = Dataset.from_pandas(train_df[["text", "label_id"]].rename(columns={"label_id": "labels"}))
    val_ds = Dataset.from_pandas(val_df[["text", "label_id"]].rename(columns={"label_id": "labels"}))
    train_ds = train_ds.map(tokenize, batched=True, remove_columns=["text"])
    val_ds = val_ds.map(tokenize, batched=True, remove_columns=["text"])

    # 빈도 역수 기반 클래스 가중치. 비어 있는 클래스가 있어도 6개 길이를 보장한다.
    counts = (
        train_df["label_id"]
        .value_counts()
        .reindex(range(len(label_mapping.MAJOR_LABELS)), fill_value=0)
        .clip(lower=1)
        .sort_index()
    )
    weights = torch.tensor(
        (len(train_df) / (len(label_mapping.MAJOR_LABELS) * counts)).to_numpy(),
        dtype=torch.float32,
    )

    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S") + f"_seed{args.seed}"
    out_dir = model_root() / "emotion_classifier" / run_id
    out_dir.mkdir(parents=True, exist_ok=True)

    training_args = TrainingArguments(
        output_dir=str(out_dir / "checkpoints"),
        seed=args.seed,
        num_train_epochs=args.epochs,
        learning_rate=args.lr,
        per_device_train_batch_size=args.batch_size,
        per_device_eval_batch_size=args.batch_size * 2,
        eval_strategy="epoch",
        save_strategy="epoch",
        save_total_limit=1,
        load_best_model_at_end=True,
        metric_for_best_model="macro_f1",
        greater_is_better=True,
        warmup_ratio=0.1,
        weight_decay=0.01,
        fp16=args.fp16 and torch.cuda.is_available(),
        logging_steps=50,
        report_to="none",
    )
    trainer = WeightedTrainer(
        class_weights=weights,
        model=model,
        args=training_args,
        train_dataset=train_ds,
        eval_dataset=val_ds,
        processing_class=tokenizer,
        compute_metrics=compute_metrics,
        callbacks=[EarlyStoppingCallback(early_stopping_patience=2)],
    )
    trainer.train()
    val_metrics = trainer.evaluate()

    trainer.save_model(str(out_dir / "model"))
    tokenizer.save_pretrained(str(out_dir / "model"))

    model_card = {
        "run_id": run_id,
        "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "task": "감정 6대분류 (기쁨/슬픔/분노/불안/상처/당황)",
        "base_model": args.base_model,
        "base_revision": args.base_revision,
        "data_version": args.data_version,
        "mapping_version": label_mapping.MAPPING_VERSION,
        "prefix_mapping_verified": label_mapping.PREFIX_MAPPING_VERIFIED,
        "preprocess_code_sha256": preprocess_code_sha(),
        "split": {
            "method": data_meta.get("split_method"),
            "seed": data_meta.get("seed"),
            "counts": data_meta.get("counts"),
            "label_distribution": data_meta.get("label_distribution"),
        },
        "hyperparameters": {
            "seed": args.seed,
            "max_length": args.max_length,
            "epochs": args.epochs,
            "learning_rate": args.lr,
            "batch_size": args.batch_size,
            "fp16": bool(args.fp16 and torch.cuda.is_available()),
            "class_weights": [round(float(w), 4) for w in weights],
            "loss": "CrossEntropyLoss(빈도 역수 가중)",
        },
        "val_metrics": {k: float(v) for k, v in val_metrics.items() if isinstance(v, (int, float))},
        "notes": "일반 감정 분류기이며 자살·자해 위험 탐지 용도로 쓰지 않는다.",
    }
    (out_dir / "model_card.json").write_text(
        json.dumps(model_card, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    print(f"\n학습 완료. run_id={run_id}")
    print(f"  모델: {out_dir / 'model'}")
    print(f"  val macro-F1: {val_metrics.get('eval_macro_f1'):.4f}")
    print("evaluate.py로 test 평가와 UI 노출 판정을 마친 뒤 사용하세요.")


if __name__ == "__main__":
    main()
