# 화면 캡처

README에 쓰는 실제 앱 화면을 모아 둔다. 개인 정보가 없는 QA 데이터로 실행한
화면만 촬영하며, 기능을 설명하는 캡처와 콘셉트 일러스트를 구분한다.

```text
docs/screenshots/web/
├─ 01-home-wide.webp
├─ 02-plant-museum-wide.webp
├─ 02-record-wide.webp
├─ 03-calendar-wide.webp
├─ 03-my-room-wide.webp
├─ 04-garden-wide.webp
├─ 05-shop-wide.webp
├─ 06-museum-detail-wide.webp
├─ 07-reports-wide.webp
├─ 08-character-growth-atlas-wide.webp
└─ 09-expedition-battle-wide.webp
```

웹 화면은 1280px 이상의 데스크톱 뷰포트에서 촬영하고 WebP로 저장한다. 같은
화면을 다시 찍을 때는 파일명을 유지해 README 링크가 바뀌지 않게 한다.

`mobile/`에는 홈, 일기, 퀘스트, 박물관, 상점, 정원과 아래 최신 화면을 보관한다.

```text
07-trial-welcome.webp           비회원 3분 체험 진입 화면
08-expedition-battle.webp       (구) 예약형 수동 전투 화면
09-expedition-skill-detail.webp (구) 스킬 길게 누르기 상세 화면
10-expedition-combat.gif        (구) 예약형 전투 브라우저 녹화
11-adventure-hub.webp           이어서 모험하기 카드가 있는 모험 허브
12-stage-map.webp               기억서고 8스테이지 지도
13-stage-preview.webp           등장 엉킴·약점·예상 시간 스테이지 시트
14-wave-battle.webp             카드 독·예고·집중력이 담긴 웨이브 전투
15-elite-battle.webp            큰 엉킴(서가 뒤엉킴) 전투
16-expedition-return.webp       함께 돌아온 탐험대 귀환 요약
17-sequential-combat.gif        카드 탭 → 즉시 행동 → 다음 차례 흐름 녹화
18-wave-clear.gif               엉킴이 풀리고 다음 웨이브가 나타나는 녹화
19-tangle-release.gif           큰 엉킴이 풀려나는 승리 녹화
```

8~10번 구버전 전투 화면은 스테이지 개편 이전 기록으로만 남긴다. README에는
11번 이후의 최신 화면만 사용한다.

`docs/readme/mongroo-emotion-growth-hero.webp`는 기능 증빙 화면이 아니라 README
첫 화면에 사용하는 콘셉트 일러스트다. 실제 기능 설명에는 항상 `screenshots/`
아래의 실행 화면이나 녹화를 사용한다.
