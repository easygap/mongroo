# 탐험 전투 VFX v3 — 비식물 고유기 첫 세로 슬라이스

생성일: 2026-08-10
범위: 그림싹(암살자) 고유 I `venom_seam` / 맹독 틈베기
도구: Codex 내장 ImageGen `stylized-concept` + ImageGen 스킬의
`remove_chroma_key.py`
판정: **앱 연결 완료 / production candidate / production ready 아님**

씨앗 기반 세계관을 식물 공격으로만 해석하지 않는 첫 실전 자산이다. 검은 단검,
보라색 독 홈, 독성 접촉점이 `anticipation → release → travel → pre-contact → contact →
reaction → recovery` 순서로 실제로 바뀐다. 공격 픽셀은 코드로 그리지 않았고 일곱
프레임 모두 별도의 ImageGen 원화다. 빌더는 배경 제거, 캔버스 좌표 배치, 리사이즈,
WebP 파생과 QA만 수행한다.

## 1. 산출물

- chroma 원본: `sources/venom-seam/` 7 PNG
- 투명 master: `alpha/venom-seam/` 7 RGBA PNG
- runtime: `app/assets/adventure/effects/venom-seam-v1/` 7 RGBA WebP,
  각 576×288
- light/dark QA: `qa/venom-seam-v1-light-dark.webp`
- 재생 QA: `qa/venom-seam-v1-preview.webp`
- 원본·alpha·runtime SHA-256, phase, duration, bbox, coverage:
  `manifest.json`

앱은 `effect_key: venom_seam`을 위 runtime 폴더에 연결한다. 프레임 좌표는
`120 → 205 → 300 → 385 → 450 → 450 → 450px`에 베이크되어 단검이 왼쪽 발사점에서
오른쪽 접촉점까지 이동한다. 런타임 painter나 transform이 공격 경로를 대신 만들지
않는다.

## 2. ImageGen 프롬프트 계약

각 호출은 아래 공통 계약과 한 개의 phase delta를 결합했다. 스타일 참조는 프로젝트
소유 `design-system/concepts/adventure-skill-icons-v2/sources/ninja-pot/
venom-seam-v1.png` 한 장이다.

```text
Create one production-ready 2D mobile RPG attack VFX key pose for the requested
phase of the same assassin skill “Venom Seam”. Match the referenced icon’s
black-violet cel-painted fantasy style, neon toxic-green accent, crisp
silhouette, and premium Korean mobile RPG finish. Wide side-view effect
composition on a perfectly flat, uniform solid #00FF00 chroma-key background.
Direction LEFT TO RIGHT. Keep every effect pixel at least 8% away from every
canvas edge. One isolated key pose, not a sprite sheet or multiple panels.
No character, enemy, scenery, ground, shadow, border, UI, text, numbers, logo,
watermark, plant, vine, leaf, flower, or seed; no gradient or texture in the
green background.
```

| frame | phase delta | ImageGen 원본 ID |
|---:|---|---|
| 00 | 단검을 왼쪽 발사점에 낮게 세우고 독 홈이 처음 점등되는 anticipation | `exec-6e85c3fa-bd5c-4cd5-9c44-e8ffd2a4d0ac` |
| 01 | 손을 떠나는 순간, 짧고 날카로운 보라 꼬리가 생기는 release | `exec-53749637-b526-4086-a44e-8cb696340965` |
| 02 | 화면 중앙을 가르는 단검과 한 줄 독 궤적의 travel | `exec-cc15338f-771b-413d-9717-0e9f6fc04bb2` |
| 03 | 오른쪽 접촉 직전, 팁에 작은 별빛이 모이는 pre-contact | `exec-421eda87-77a4-4d88-9474-e76f5b88b3b9` |
| 04 | 단검 팁과 독성 교차광이 맞물리는 contact | `exec-346e09ee-6a6b-4039-b613-1a7c0a514f11` |
| 05 | 단검은 사라지고 독성 X 상흔만 남는 reaction | `exec-b010e16d-bb7d-4124-9478-8182b4bd67c9` |
| 06 | 끊어진 보라 절개선·독 방울·접촉 고리가 소멸하는 recovery | `exec-5f8695b9-7cf1-4dc2-8ea6-f287f6df5ebb` |

원본 ImageGen 파일은
`C:/Users/USER/.codex/generated_images/019fe938-1f3e-77b0-917d-e3cf5d8de373/`
에 보존한다.

## 3. 재현과 자동 gate

```powershell
$tool = 'C:\Users\USER\.codex\skills\.system\imagegen\scripts\remove_chroma_key.py'
python $tool --input <chroma.png> --out <alpha.png> --auto-key border `
  --soft-matte --transparent-threshold 12 --opaque-threshold 220 --despill

C:\Users\USER\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe `
  design-system\scripts\build_combat_attack_assets.py --effect venom_seam
```

빌더는 source와 alpha 존재, 4px padding, alpha coverage, 576×288 canvas, phase별
duration과 해시를 검증한다. 밝은 크림·어두운 전장 QA 양쪽에서 녹색 배경 누출 없이
단검·접촉점·잔류 상흔이 읽힌다.

## 4. production 승격 잔여

1. 실제 390×844 전장에서 그림싹 cast/hit pose와 합성한 영상 승인.
2. frame 04 contact와 서버 피해·숫자·SFX·햅틱을 ±1 frame에 동기화.
3. 색각·광과민·움직임 줄이기 및 200% 글자 설정 검수.
4. 기준/저사양 Android의 p95 frame time과 decoded peak 검증.
5. 위 증거를 manifest에 연결한 뒤에만 `production_ready:true`로 승격.
