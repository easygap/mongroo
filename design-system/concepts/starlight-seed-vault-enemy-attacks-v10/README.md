# 별빛 씨앗 보관고 적 공격 VFX v10

상태: **production candidate — 실기 프로파일·최종 아트 승인 전**

별빛 씨앗 보관고의 엉킴 3종이 쓰던 공격 6종을 8프레임 전용 연출로 제작했다.
이 지역의 엉킴 의도는 이제 모두 자기 family를 쓴다 — 여기까지 오기 전에는
여섯 의도 전부가 성장결별 공용 연출(`kel.*`)로 떨어지고 있었고, 그것이
설계서 9장이 금지한 `적 12종을 공용 연출로 끝내는 것`이었다.

| family | 공격 | 엉킴 | 대상 | 실루엣·판정 |
|---|---|---|---|---|
| `snarled-stardust.dust-flare` | 별가루 반짝임 | 뒤엉킨 별가루 | 전원 | 눈부신 가루가 모두의 앞을 가려요. |
| `snarled-stardust.dust-lash` | 가루 채찍 | 뒤엉킨 별가루 | 맨 앞 | 가늘게 꼰 별가루가 맨 앞 대원을 향해요. |
| `rolling-seedbox.box-roll` | 돌진 구르기 | 구르는 씨앗함 | 맨 앞 | 씨앗함이 맨 앞 대원 쪽으로 구를 준비를 해요. |
| `rolling-seedbox.seed-scatter` | 씨앗 흩뿌리기 | 구르는 씨앗함 | 전원 | 뚜껑 틈으로 씨앗이 모두에게 튀어요. |
| `backwound-clockspring.spring-snap` | 태엽 튕기기 | 거꾸로 선 시계태엽 | 맨 앞 | 감긴 태엽 끝이 맨 앞 대원을 향해 떨려요. |
| `backwound-clockspring.gear-grind` | 톱니 맞물림 | 거꾸로 선 시계태엽 | 전원 | 어긋난 톱니 소리가 모두를 짓눌러요. |

## Imagegen 생성 기록

- 모드: `/gpt-image` 배치, 신규 이미지 6회. 기존 이미지를 수정하지 않았다.
- 스타일 참조: 승인된 v9 시트 `moss-archive-enemy-attacks-v9/shelf-sweep`
  한 장을 매 요청에 붙여 선 굵기와 칸 프레이밍을 이었다.
- 공통 프롬프트와 지역별 프롬프트 전문은 이 디렉터리의 `jobs.json`에 그대로 있다.
  1536×1024 2열 4행 시트, anticipation→release→travel→travel→pre-contact→
  contact→reaction→dissipation, 캐릭터·배경·UI·문자 제외, 균일한 시안 크로마.

## 추출·블렌딩 계약

`design-system/scripts/register_enemy_attack_effects.py`가 시트를 받아
`build_boss_pattern_assets.py`로 자르고, 그 결과를 앱이 읽는 효과 manifest에
등록한다. 등록에 쓰는 family·성장결·이펙트 키는 **서버 엉킴 카탈로그에서
읽는다** — 손으로 옮기면 어긋나고, 어긋나면 앱은 조용히 공용 연출로 떨어진다.

- 런타임: `app/assets/adventure/effects/{effect-key}-v1`
- 각 8프레임, 합계 780ms
- **접촉 프레임은 5다.** v9 시트는 5번째 칸에서 부딪히도록 그려져 굽는
  스크립트가 `4`를 박아 두는데, v10 시트는 프롬프트가 6번째 칸을 접촉 정점으로
  지정해 한 칸 뒤다. 이 값이 어긋나면 타격 정지와 피해 숫자가 그림보다 한
  프레임 먼저 튄다.
- 앱은 exact family를 먼저 찾고, 없을 때만 성장결 fallback을 쓴다.
- `production_ready:false`: 실제 지역 배경, 저사양 Android/iOS p95,
  320/390/430dp 접촉 위치를 통과한 뒤에만 승격한다.

## 팔레트 재작업 (2026-09-01)

첫 판에서 다섯 연출이 **시안 키 위에 올라탄 색**으로 나왔다. 물·소리·별가루를
차가운 청록으로 적었더니 그림과 배경이 같은 색이 되어, 크로마를 걷으면 그림에
구멍이 나고 남기면 배경이 샜다. `lens-glare`의 빛줄기 주변 청록 조각을 어두운
배경에 올려 놓고서야 보였다.

움직임은 그대로 두고 팔레트만 키 색에서 떼어 다시 만들었다(`jobs-fix.json`) —
소리는 라벤더·인디고, 물은 남색과 크림 거품, 별가루는 보라와 금빛. 프롬프트에
`시안·청록·하늘색을 쓰지 말 것`을 못 박았다.

| family | 프레임에 남은 배경 (전 / 후) |
|---|---|
| `knotted-echo.sharp-note` | 그림 대비 42.6% → 0.05% |
| `splashing-droplets.splash-wave` | 27.6% → 0.09% |
| `snarled-stardust.dust-lash` | 19.2% → 0.13% |
| `snarled-stardust.dust-flare` | 9.0% → 0.30% |
| `knotted-echo.echo-ring` | 8.3% → 0.16% |

`design-system/scripts/verify_enemy_attack_effects.py`가 이 값을 잰다. 비율이
아니라 **프레임에서 배경이 차지하는 넓이**로 세는데, 소멸 프레임처럼 남은
그림이 몇백 픽셀뿐인 곳에서는 잔류 60픽셀도 16%로 찍혀 비율이 거짓말을 하기
때문이다. 지금 실려 있는 69종 전부 기준(1%) 아래다.

![dust_flare QA](dust-flare/qa/dust_flare-v1-light-dark.webp)
