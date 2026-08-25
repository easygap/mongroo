# 화면 캡처

README에 쓰는 실제 앱 화면을 모아 둔다. 개인 정보가 없는 QA 데이터로 실행한
화면만 촬영하며, 기능을 설명하는 캡처와 콘셉트 일러스트를 구분한다.

## README가 링크하는 캡처 — `web/readme-current/`

README 본문이 실제로 참조하는 최신 캡처만 여기 둔다. 2026-08-25 출시 후보
웹 빌드를 QA 계정 하나로 연속 실행해 같은 데이터에서 촬영했다.

```text
mood-to-growth.gif   일기 작성 → 저장 → 화분 반응 → 홈 성장까지 (480x1040 DPR1 실시간 녹화, 12fps)
home.webp            데스크톱 1280 홈
home-mobile.webp     모바일 390 홈
diary-write.webp     일기 작성 화면
calendar.webp        기록 달력
report.webp          월간 회고
museum.webp          마음 식물 박물관
room.webp            소품과 동행 친구를 배치한 방
shop.webp            상점
adventure-hub.webp   정원 · 탐험 탭 (오늘의 성장 효율)
trial.webp           비회원 3분 체험
dungeon-walk.gif     방향키로 던전을 한 칸씩 걷는 장면 (520x1126 DPR1 스크린캐스트, 10fps)
```

데스크톱은 1280x860, 모바일은 390x844 뷰포트에서 DPR2로 찍은 뒤 각각 1280px,
480px 폭 WebP로 저장한다. 같은 화면을 다시 찍을 때는 파일명을 유지해 README
링크가 바뀌지 않게 한다.

GIF는 프레임 합성 없이 실시간 화면 녹화를 리샘플한 것이다. CDP
`Page.startScreencast`가 CSS 해상도로만 나오므로 뷰포트를 키워 DPR1으로 찍고
일정 fps로 다시 뽑는다.

## 보관용 캡처

`web/`의 01~09·14~16번과 `mobile/`의 07번 이후는 기능별 보관 캡처다. 촬영
시점이 서로 달라 README 설명에는 `readme-current/`를 우선한다.

`mobile/`에서 마케팅·완료 증빙에 쓰지 않는 항목:

- 08~10번: 스테이지 개편 이전의 예약형 전투
- 14·15·17~19번: v2.0 기능 prototype 기록
- 32·33번: 아날로그 걷기 시절의 자유 이동. 지금은 칸 단위 걷기다

README 전투 설명은 출시 후보 Flutter Web 빌드를 360x732 모바일 뷰포트에서
실행해 촬영한 20~22·24번만 사용한다. 2026-08-11 QA 전용 데이터로 같은 수호전을
직접 조작했으며, 정지 화면과 GIF에 콘셉트 HUD나 사후 합성 프레임을 섞지 않았다.

2026-08-24 이전에 찍은 던전 캡처(`web/10~13`, 옛 `readme-current/expedition-*`)는
출시 빌드에서 감춘 계측 표시가 화면에 남아 있어 모두 삭제했다. 던전을 다시
찍을 때는 계측 표시가 없는지 확인한다.

## 콘셉트 이미지 구분

- `design-system/concepts/adventure-combat-first-v1/combat-first-visual-target-v1.png`는
  ImageGen으로 만든 배치 기준안이며 실제 앱 캡처가 아니다. 스토어 화면이나 구현
  증빙으로 쓸 수 없고, 문서에서는 반드시 `visual target`으로 표기한다.
- `design-system/character-lineage-previews/*.webp`는 앱이 쓰는 성장 스프라이트를
  그대로 배치한 계보 시트다. 성장 단계 설명에는 쓰되 화면 캡처로 표기하지 않는다.
- `docs/readme/mongroo-emotion-growth-hero.webp`는 콘셉트 일러스트다. 기능 설명에는
  항상 `screenshots/` 아래의 실행 화면이나 녹화를 사용한다.
