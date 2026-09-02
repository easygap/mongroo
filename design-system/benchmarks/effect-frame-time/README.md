# 전투 연출 프레임 타임 벤치마크

`production_ready` 게이트의 마지막 항목인 **프레임 타임**을 실제 래스터
파이프라인에서 재기 위한 하네스다. `verify_effect_production_gate.py`가 재는
정적 항목(무결성·크로마·가독성·메모리)과 달리, 이것은 연출을 실제로 **재생해
보고** 잰다.

## 왜 브라우저가 아니라 데스크톱인가

`docs/performance.md` 3장이 정한 절차는 릴리스 Web을 Chrome CDP로 재는 것이고,
그 문서는 `창이 최소화되거나 가려져 Chrome이 rAF를 1Hz로 제한한 표본은
폐기한다`고 못 박는다. 이 저장소를 다루는 에이전트 세션의 브라우저 패널은
숨어 있어서, rAF가 실제로 1Hz로 묶인다 — 40프레임을 받는 데 45초가 넘게 걸려
표본이 성립하지 않았다.

그래서 브라우저를 우회해 Flutter가 직접 주는 `FrameTiming`을 쓴다. Windows
데스크톱 profile 빌드는 가시성 스로틀이 없고, UI 스레드와 래스터 스레드를
나눠서 준다.

## 재는 것

`app/assets/adventure/effects/manifest.json`의 연출 전부를 선언된 프레임 길이
그대로 이어 재생하면서 `FrameTiming`을 모은다. 앞의 90프레임은 셰이더 워밍업과
첫 디코드가 섞이므로 버린다.

- `build` — UI 스레드가 프레임을 만드는 데 쓴 시간
- `raster` — 래스터 스레드가 그리는 데 쓴 시간
- `total` — vsync 대기를 포함한 프레임 간격

**합격 판단에 쓸 값은 `raster`와 `build`다.** `total`은 모니터 주사율에
묶여서(이 기계는 약 120Hz라 8.3ms 근처) 연출의 비용이 아니라 화면의 리듬을
보여 준다.

## 무엇을 재지 **않는가**

- **저사양 Android·iOS.** 이 기계에는 Android SDK도 실기기도 없다. 데스크톱
  GPU는 모바일의 발열·전력 제한·메모리 압박을 대신하지 않는다.
- **전장 전체 프레임.** 배경·엉킴 몸체·캐릭터·HUD를 뺀 **연출 레이어만** 그린다.
  그래서 나오는 값은 `이 에셋이 프레임 예산에서 얼마를 가져가는가`이지
  `전투 화면이 몇 프레임인가`가 아니다. 전자가 에셋에 물을 수 있는 값이다.

## 돌리는 법

하네스는 `bench.dart` 한 장이다. 스캐폴드는 재생성해 쓴다(러너를 저장소에
넣지 않는다).

```bash
flutter create --platforms=windows --project-name fxbench /tmp/fxbench
cp design-system/benchmarks/effect-frame-time/bench.dart /tmp/fxbench/lib/main.dart
cd /tmp/fxbench && flutter run -d windows --profile
```

`bench.dart` 위쪽의 `repo` 상수를 저장소 경로로 맞춘다. 표본이 모이면
`FXBENCH_BEGIN`과 `FXBENCH_END` 사이에 JSON 한 줄을 찍고 종료한다.

결과는 `docs/performance.md`에 적는다.
