# 탐험 전투 VFX v2 제작·검수 기록

최종 갱신: 2026-08-10
범위: 플레이어 `care_vines`, 돌비늘 장부지기 `ledger_claw`
현재 판정: **production candidate / production ready 아님**

이 디렉터리는 공격 궤적을 코드 도형으로 그리거나 한 장의 자동 sprite sheet를 잘라
쓴 결과가 아니다. 내장 ImageGen으로 한 번에 한 동작만 생성·검수하고, 승인된 앞뒤
동작을 참조한 기술 in-between을 더해 family별 10개 원본을 만들었다. 빌더는 자홍색
배경 제거, 고정 canvas·pivot 정규화, WebP 파생과 QA만 수행한다. 공격 본체 픽셀과
모션 형태는 생성하지 않는다.

## 1. 산출물과 상태

| family | 방향·정체성 | 원본 | runtime | QA | 판정 |
| --- | --- | --- | --- | --- | --- |
| `care_vines` | 플레이어 왼쪽 손 → 수호자 오른쪽, 황금빛 생덩굴 | `sources/care-vines/` 10 PNG | `app/assets/adventure/effects/care-vines-v2/` 10 WebP | `qa/care-vines-v2-{light-dark,preview}.webp` | 후보 |
| `ledger_claw` | 수호자 오른쪽 앞발 → 선두 대원 왼쪽, 이끼 돌발톱 3개 | `sources/ledger-claw/` 10 PNG | `app/assets/adventure/effects/ledger-claw-v2/` 10 WebP | `qa/ledger-claw-v2-{light-dark,preview}.webp` | 후보 |

`manifest.json`은 원본·alpha·runtime SHA-256, frame별 phase·duration·bbox·coverage,
origin·target·contact를 기록한다. `production_ready:false`인 이유는 390×844 실제 기기
합성 영상, actor attack/hit pose, contact SFX·햅틱 ±1 frame, profile trace가 아직
승인되지 않았기 때문이다.

## 2. ImageGen 방식과 입력 역할

- 도구/모드: 내장 ImageGen `stylized-concept`; 중간 동작은 승인 프레임 기반 image edit.
- `care_vines`: 최초 여섯 장은 각 phase의 독립 key pose, 네 장은 인접 승인본을 함께
  본 기술 in-between이다.
- `ledger_claw`: 첫 장만
  `app/assets/adventure/ledger-keeper-attack-v1-mobile.webp`를 **색·윤곽·광원 정체성
  참조**로 사용했다. 수호자 몸은 출력하지 않았다. 이후 장은 직전 또는 앞뒤 승인
  발톱 프레임만 참조해 동일한 뿌리 축과 세 갈래 구조를 잠갔다.
- 모든 출력은 완성 시트가 아닌 단일 effect-only pose이고, 원본 ImageGen 파일은
  `C:/Users/USER/.codex/generated_images/019fe938-1f3e-77b0-917d-e3cf5d8de373/`에
  그대로 보존했다.

## 3. 재현용 프롬프트 계약

### 3.1 `care_vines`

공통 골격:

```text
Create one isolated effect-only animation pose for a premium hand-painted 2D mobile RPG.
The same living golden-green vine must remain continuous from a fixed root at far screen-left:
warm dark-brown outline, three-value cel shading, upper-left light, one main stem, a small set of
large readable leaves and amber nodes. Direction LEFT TO RIGHT. Draw only the attack object for
the requested phase. One flat solid exact #FF00FF chroma background. One frame only, not a grid
or spritesheet. No character, target, hand, scenery, UI, text, generic beam, blur trail, floor,
shadow, gradient, grain, watermark, or micro-particle spray. Keep every edge inside the canvas.
```

| runtime frame | phase 지시 | 생성 원본 ID | 역할 |
| ---: | --- | --- | --- |
| 00 | 손 가까이에 감긴 새순, 힘을 모음 | `exec-67c51eca-ca47-4e39-970a-9230412e9eb8` | key |
| 01 | 감긴 줄기가 처음 풀리는 중간형 | `exec-e0efdf30-8611-4807-81a3-198c1ff6158f` | in-between |
| 02 | 새순 방출, 뿌리 축 유지 | `exec-9e971ab4-1c4c-4512-9b1e-7e967ad93dcd` | key |
| 03 | 방출과 비행 중간, 줄기 연결 유지 | `exec-f33fe0f9-3e06-4696-bbdc-cbb6a801ba1e` | in-between |
| 04 | 화면 중간까지 실제로 뻗은 비행체 | `exec-5aa397d4-bef4-4678-bdd3-aec7269edab5` | key |
| 05 | 선단이 목표 접촉점을 처음 감쌈 | `exec-3a6dd94b-e41c-4db2-93b8-ffbd93491380` | key |
| 06 | 접촉과 최대 매듭 사이의 조임 | `exec-cdfcb3a8-c3c8-4624-bfb0-6d1d787c19c8` | in-between |
| 07 | 잎·매듭이 읽히는 최대 impact | `exec-4b949e6d-7e7c-4314-98b0-0d58f7d5e2c0` | key |
| 08 | 접촉을 풀고 되감기는 반동 | `exec-aaa3de29-2d26-43c9-b5d6-1ca532022bb3` | in-between |
| 09 | 뿌리 쪽으로 회수되는 끝동작 | `exec-c994cac7-fb8e-42b1-87f9-e50382782104` | key |

### 3.2 `ledger_claw`

최초 정체성 프롬프트:

```text
Create ONE isolated effect-only animation key pose for a premium 2D mobile RPG attack, using
the reference only for the friendly moss-stone guardian's palette, warm-brown outline weight,
hand-painted three-value cel shading, and cyan spiral accent. Do not draw the turtle or any
character. Attack identity: LEDGER CLAW, three broad connected stone-and-parchment claw ribbons
with moss-sage edge plates and a restrained cyan etched-memory glow, a physical readable attack
body rather than a generic energy wave. Direction RIGHT TO LEFT. Keep the shared root/pivot fixed
near screen-right. Flat solid exact #FF00FF chroma background. One frame only, not a spritesheet
or grid. No UI, text, letters, particles, floor, shadow, gradient, grain, watermark, or tiny noise.
```

후속 호출은 위 정체성과 직전 승인본을 고정하고 아래 phase delta만 바꿨다.

| runtime frame | phase delta | 생성 원본 ID | 참조 역할 |
| ---: | --- | --- | --- |
| 00 | 세 발톱을 오른쪽 축에 짧게 접어 힘을 모음 | `exec-d3607f1c-e9b5-47ce-b93e-5f00551a3432` | 최초 생성본의 압축 edit |
| 01 | 세 발톱이 왼쪽으로 열리며 방출 | `exec-a6a64b46-e8e0-40a7-91a1-307b2eeefe22` | 수호자 palette/style ref |
| 02 | 00과 01 사이에서 한 단계 더 uncoil | `exec-c734b2d8-9cf8-4e20-b9b2-cd07668ea3f3` | 앞뒤 승인본 in-between |
| 03 | 팁이 화면 왼쪽 10~14%까지 도달 | `exec-1d1641f4-0669-4eb7-b98d-6439eb7716a0` | 직전 승인본 edit |
| 04 | 빈 접촉점에 세 팁이 모이고 작은 별·큰 돌조각 3~5개 | `exec-2e008f03-f741-48a2-b09b-df8aa6c1a18c` | 직전 승인본 edit |
| 05 | 접촉점을 더 누르는 최대 impact, 큰 돌조각 5~7개 | `exec-9dc0fad6-facc-4e18-864e-8812653f4f83` | 직전 승인본 edit |
| 06 | 왼쪽 팁을 22% 되당기고 접촉광을 축소 | `exec-15fa8ae1-8c41-4686-b8f5-14bb677b3475` | impact recoil edit |
| 07 | 최대 길이와 접힘 사이 중간 회수 | `exec-d5d4e3d8-86c9-4310-987c-6bb4250b5669` | 앞뒤 승인본 in-between |
| 08 | 오른쪽 축 근처로 접힌 회수 자세 | `exec-3410e25c-582b-4091-8854-bdfb117c743b` | recoil/compact in-between |
| 09 | 더 짧게 접히고 청록 문양이 약해진 종료 | `exec-516aff26-51a5-4516-92b4-946c7c12e5e9` | compact edit |

## 4. 빌드와 자동 gate

```powershell
C:\Users\USER\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe design-system\scripts\build_combat_attack_assets.py
C:\Users\USER\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe design-system\scripts\build_combat_attack_assets.py --report-only
```

빌더는 원본 비율과 무관하게 중앙 2:1 전투 canvas를 계산하고 576×288로 파생한다.
`ledger_claw`는 오른쪽 발사축을 x=556에 맞추되 형태를 다시 그리지 않는다. 모든 frame은
4px padding, alpha coverage 범위, 자홍색 잔류 상한, origin drift를 통과해야 한다.
QA sheet는 같은 RGBA를 짙은 전장색과 크림색 배경에 각각 합성하므로 washed alpha와
자홍 fringe를 동시에 찾을 수 있다.

## 5. production 승격 잔여

1. 390×844 실제 전장에서 actor pose와 합성한 1×·2×·짧은 연출·저감 모션 영상 승인.
2. `release/contact/reaction`과 서버 피해, SFX, 햅틱, 숫자를 ±1 frame에 동기화.
3. 기준 Android·저사양 Android profile에서 p95 frame time과 decoded peak 검증.
4. `ledger_claw` 외 `record_wave`, `seal_crush`도 각각 다른 공격 family로 제작.
5. 위 증거를 manifest에 붙인 뒤에만 `production_ready:true`로 변경.
