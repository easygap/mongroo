"""Ollama 후보 모델 벤치마크 (M0 스파이크).

고정 한국어 자기성찰 프롬프트 세트를 순차(동시성 1)로 실행하면서
TTFT, tokens/sec, 전체 지연, 응답 길이, VRAM 사용량을 기록한다.
결과는 docs/benchmarks/ 아래 JSON과 Markdown으로 저장한다.

측정값 출처:
- TTFT: 스트리밍 첫 청크 수신까지의 벽시계 시간
- tokens/sec: Ollama 응답의 eval_count / eval_duration
- VRAM: nvidia-smi --query-gpu 파싱 (없으면 null)

실행 예:
  python bench_ollama.py --model qwen3:8b-q4_K_M
  python bench_ollama.py --model exaone3.5:7.8b --temperature 0.2
"""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

import httpx

BENCH_DIR = Path(__file__).resolve().parent.parent.parent / "docs" / "benchmarks"

# 제품의 식물 대화와 비슷한 조건을 만들기 위한 최소 시스템 프롬프트.
# 실제 서비스 프롬프트(페르소나, 단계, 금지 규칙, JSON schema)는 서버 쪽 자산이다.
SYSTEM_PROMPT = (
    "너는 사용자가 키우는 화분 속 식물이야. 사용자가 오늘 겪은 일과 감정을 "
    "스스로 정리하도록 돕는 짧은 대화를 나눠. 한 번에 질문은 하나만 하고, "
    "진단이나 치료 조언은 하지 마. 존댓말 없이 부드러운 반말로, 3~4문장 이내로 답해."
)

# 자기성찰 대화 시나리오. 벤치마크 비교를 위해 고정한다.
PROMPTS: tuple[str, ...] = (
    "오늘 회사에서 실수를 해서 하루 종일 그 생각만 났어.",
    "요즘 잠들기 전에 생각이 많아져서 자꾸 늦게 자.",
    "친구랑 사소한 일로 다퉜는데 먼저 연락하기가 망설여져.",
    "이직 준비를 시작했는데 잘하고 있는 건지 모르겠어.",
    "주말 내내 아무것도 안 했더니 오히려 마음이 더 무거워졌어.",
    "다음 주에 발표가 있는데 준비를 했는데도 계속 긴장돼.",
    "가족이랑 얘기할 때마다 서운한 마음이 조금씩 쌓이는 것 같아.",
    "생각해 보니 요즘 나 자신을 칭찬해 준 적이 한 번도 없더라.",
)

WARMUP_PROMPT = "안녕, 오늘 하루 어땠는지 물어봐 줄래?"


def gpu_snapshot() -> dict | None:
    """nvidia-smi로 VRAM 사용량(MiB)을 읽는다. GPU가 없으면 None."""
    try:
        out = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=name,memory.used,memory.total",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True,
            text=True,
            timeout=10,
            check=True,
        ).stdout.strip()
    except (FileNotFoundError, subprocess.SubprocessError):
        return None
    name, used, total = [x.strip() for x in out.splitlines()[0].split(",")]
    return {"gpu": name, "vram_used_mib": int(used), "vram_total_mib": int(total)}


def run_prompt(
    client: httpx.Client, host: str, model: str, prompt: str, options: dict, timeout_s: float
) -> dict:
    """프롬프트 하나를 스트리밍으로 실행하고 측정값을 돌려준다."""
    payload = {
        "model": model,
        "stream": True,
        "options": options,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
        ],
    }
    started = time.perf_counter()
    ttft = None
    text_parts: list[str] = []
    final: dict = {}
    try:
        with client.stream(
            "POST", f"{host}/api/chat", json=payload, timeout=timeout_s
        ) as response:
            response.raise_for_status()
            for line in response.iter_lines():
                if not line:
                    continue
                chunk = json.loads(line)
                if ttft is None:
                    ttft = time.perf_counter() - started
                text_parts.append(chunk.get("message", {}).get("content", ""))
                if chunk.get("done"):
                    final = chunk
    except httpx.TimeoutException:
        return {
            "prompt": prompt,
            "timeout": True,
            "total_s": round(time.perf_counter() - started, 3),
        }

    total_s = time.perf_counter() - started
    eval_count = final.get("eval_count")
    eval_duration_ns = final.get("eval_duration")
    tokens_per_sec = (
        round(eval_count / (eval_duration_ns / 1e9), 2)
        if eval_count and eval_duration_ns
        else None
    )
    text = "".join(text_parts)
    return {
        "prompt": prompt,
        "timeout": False,
        "ttft_s": round(ttft, 3) if ttft is not None else None,
        "total_s": round(total_s, 3),
        "tokens_per_sec": tokens_per_sec,
        "eval_count": eval_count,
        "prompt_eval_count": final.get("prompt_eval_count"),
        "response_chars": len(text),
        "response_preview": text[:120],
    }


def summarize(results: list[dict]) -> dict:
    ok = [r for r in results if not r["timeout"]]

    def stats(key: str) -> dict | None:
        values = [r[key] for r in ok if r.get(key) is not None]
        if not values:
            return None
        return {
            "mean": round(statistics.mean(values), 3),
            "median": round(statistics.median(values), 3),
            "min": round(min(values), 3),
            "max": round(max(values), 3),
        }

    return {
        "prompts": len(results),
        "timeouts": sum(1 for r in results if r["timeout"]),
        "ttft_s": stats("ttft_s"),
        "total_s": stats("total_s"),
        "tokens_per_sec": stats("tokens_per_sec"),
        "response_chars": stats("response_chars"),
    }


def build_markdown(record: dict) -> str:
    s = record["summary"]
    v = record["vram"]
    lines = [
        f"# Ollama 벤치마크 — {record['model']}",
        "",
        f"- 실행 시각: {record['created_at']}",
        f"- 양자화: {record['quantization']}",
        f"- 옵션: num_ctx={record['options']['num_ctx']}, "
        f"num_predict={record['options']['num_predict']}, "
        f"temperature={record['options']['temperature']}, 동시성 1(순차)",
        f"- timeout 기준: {record['timeout_s']}초 / 발생 {s['timeouts']}건",
        "",
        "## VRAM",
        "",
        f"- 실행 전: {v['before']}",
        f"- 워밍업 직후(모델 로드 포함): {v['after_warmup']}",
        f"- 실행 중 최대: {v['peak']}",
        "",
        "## 요약",
        "",
        "| 지표 | mean | median | min | max |",
        "|------|------|--------|-----|-----|",
    ]
    for label, key in (
        ("TTFT (s)", "ttft_s"),
        ("전체 지연 (s)", "total_s"),
        ("tokens/sec", "tokens_per_sec"),
        ("응답 길이 (chars)", "response_chars"),
    ):
        st = s[key]
        if st:
            lines.append(
                f"| {label} | {st['mean']} | {st['median']} | {st['min']} | {st['max']} |"
            )
        else:
            lines.append(f"| {label} | - | - | - | - |")
    lines += [
        "",
        "## 프롬프트별 결과",
        "",
        "| # | TTFT (s) | 전체 (s) | tok/s | chars | timeout |",
        "|---|----------|----------|-------|-------|---------|",
    ]
    for i, r in enumerate(record["results"], start=1):
        if r["timeout"]:
            lines.append(f"| {i} | - | {r['total_s']} | - | - | O |")
        else:
            lines.append(
                f"| {i} | {r['ttft_s']} | {r['total_s']} | "
                f"{r['tokens_per_sec']} | {r['response_chars']} | - |"
            )
    lines += [
        "",
        "## 한국어 품질·안전 메모",
        "",
        "- 응답 본문은 JSON의 response_preview로 확인하고, 품질 소견과",
        "  prompt_probe_set.md 안전 회귀 결과를 여기에 수기로 기록한다.",
        "",
    ]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", required=True, help="예: qwen3:8b-q4_K_M")
    parser.add_argument("--quant", default=None, help="양자화 표기. 생략 시 모델 태그에서 추정")
    parser.add_argument("--num-ctx", type=int, default=4096)
    parser.add_argument("--num-predict", type=int, default=384)
    parser.add_argument("--temperature", type=float, default=0.3)
    parser.add_argument("--timeout", type=float, default=120.0, help="프롬프트당 timeout(초)")
    parser.add_argument("--host", default="http://127.0.0.1:11434")
    args = parser.parse_args()

    options = {
        "num_ctx": args.num_ctx,
        "num_predict": args.num_predict,
        "temperature": args.temperature,
    }
    quant = args.quant or (args.model.split("-", 1)[1] if "-" in args.model else "unknown")

    vram_before = gpu_snapshot()
    peak = vram_before

    with httpx.Client() as client:
        try:
            client.get(f"{args.host}/api/version", timeout=5)
        except httpx.HTTPError:
            raise SystemExit(
                f"Ollama({args.host})에 연결할 수 없습니다. Ollama를 먼저 실행하세요."
            )

        print(f"워밍업 (모델 로드 포함): {args.model}")
        warmup = run_prompt(client, args.host, args.model, WARMUP_PROMPT, options, args.timeout)
        vram_after_warmup = gpu_snapshot()
        if vram_after_warmup:
            peak = max(peak or vram_after_warmup, vram_after_warmup, key=lambda x: x["vram_used_mib"])

        results = []
        for i, prompt in enumerate(PROMPTS, start=1):
            print(f"[{i}/{len(PROMPTS)}] {prompt[:30]}...")
            r = run_prompt(client, args.host, args.model, prompt, options, args.timeout)
            results.append(r)
            snap = gpu_snapshot()
            if snap and (peak is None or snap["vram_used_mib"] > peak["vram_used_mib"]):
                peak = snap

    record = {
        "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "model": args.model,
        "quantization": quant,
        "host": args.host,
        "options": options,
        "timeout_s": args.timeout,
        "concurrency": 1,
        "warmup": {"total_s": warmup.get("total_s"), "timeout": warmup.get("timeout")},
        "vram": {"before": vram_before, "after_warmup": vram_after_warmup, "peak": peak},
        "results": results,
        "summary": summarize(results),
    }

    BENCH_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    safe_model = args.model.replace(":", "_").replace("/", "_")
    json_path = BENCH_DIR / f"{stamp}_{safe_model}.json"
    md_path = BENCH_DIR / f"{stamp}_{safe_model}.md"
    json_path.write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
    md_path.write_text(build_markdown(record), encoding="utf-8")

    s = record["summary"]
    print(f"\n완료: timeout {s['timeouts']}건 / TTFT {s['ttft_s']} / tok/s {s['tokens_per_sec']}")
    print(f"저장: {json_path}\n      {md_path}")


if __name__ == "__main__":
    main()
