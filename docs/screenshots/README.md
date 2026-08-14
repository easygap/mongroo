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
├─ 09-expedition-battle-wide.webp
├─ 10-expedition-walk-heartwood-wide.webp
├─ 11-region-moss-archive-wide.webp
├─ 12-region-echo-well-wide.webp
├─ 13-region-starlight-vault-wide.webp
├─ 14-expedition-screen-wide.webp
├─ 15-adventure-hub-wide.webp
└─ 16-expedition-free-walk.gif
```

10~16번은 2026-08-14 출시 후보 빌드를 1280×860 데스크톱 뷰포트에서 실행해 촬영했다.
네 지역 지형과 그 위를 걷는 캐릭터, 지나온 발자국이 모두 실제 렌더링이며 지도
영역만 잘라 냈다. 16번은 가상 스틱을 눌러 회랑을 따라 걷는 장면을 무편집으로 녹화한
뒤 12fps GIF로 옮긴 것이고, 프레임을 덧그리거나 이어 붙이지 않았다.

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
14-wave-battle.webp             (v2.0 prototype) 분리 패널·카드 독 웨이브 전투
15-elite-battle.webp            (v2.0 prototype) 절차적 큰 엉킴 전투
16-expedition-return.webp       함께 돌아온 탐험대 귀환 요약
17-sequential-combat.gif        (v2.0 prototype) 카드 탭 순차 행동 녹화
18-wave-clear.gif               (v2.0 prototype) 스냅샷 웨이브 교체 녹화
19-tangle-release.gif           (v2.0 prototype) 절차적 큰 엉킴 풀림 녹화
20-integrated-battle.webp        v2.2 통합 전장·6아이콘 벨트 실제 화면
21-player-skill-contact.gif      준비→이동→접촉→피격 플레이어 스킬 실제 녹화
22-enemy-skill-contact.gif       방어→적 공격→접촉→다음 라운드 실제 녹화
23-emotion-matchup.webp          (미촬영) 여섯 성장결 약점↑·내성↓와 선택 스킬 벨트
24-skill-long-press.webp         계수·단계·상성·재사용 턴 길게 누르기 실제 화면
25-imagegen-skill-icons.webp     (미촬영) 102개 도색 아이콘의 128·64·48·32px QA
26-battle-trail.gif              (미촬영) 접근→조우→전투→풀려남→전진 연속 화면
27-combat-first-hud.webp         (미촬영) 전장 72~78%·상단 8점 rail·하단 6아이콘 dock
28-player-enemy-contact-grid.webp (미촬영) 플레이어/적 origin→travel→contact→reaction 비교
29-blend-backgrounds.webp        (미촬영) 네 지역 밝음/어두움 alpha fringe·depth·shadow QA
30-store-gameplay-15s.mp4        (미촬영) 실제 빌드 준비→접촉→피격→환경 복원 15초 무편집 증빙
31-skill-book-library.webp       마음결 기록서 프리셋·두 선택 칸·서고 실제 화면
32-expedition-map.webp           지도 위 자유 이동 시작 자리(마음나무 관측실)
33-expedition-free-walk.webp     가상 스틱으로 회랑을 걸은 뒤 남은 발자국
```

8~10번은 스테이지 개편 이전, 14·15·17~19번은 v2.0 기능 prototype 기록이다.
v2.2의 통합 전장·6아이콘 벨트·정식 플레이어/적 스프라이트가 아니므로 마케팅·완료
증빙에 사용하지 않는다. README 전투 설명은 출시 후보 Flutter Web 빌드를 360×732
모바일 뷰포트에서 실행해 촬영한 20~22·24번만 사용한다. 2026-08-11 QA 전용 데이터로
같은 수호전을 직접 조작했으며, 정지 화면 2장과 입력부터 결과까지 이어지는 GIF 2개에
콘셉트 HUD나 사후 합성 프레임을 섞지 않았다.

`design-system/concepts/adventure-combat-first-v1/combat-first-visual-target-v1.png`는
ImageGen으로 만든 배치 기준안이며 실제 앱 캡처가 아니다. 26~30번의 구현 증빙을 대신하거나
스토어 화면에 사용할 수 없고, 문서에서는 반드시 `visual target`으로 표기한다.

30번은 콘셉트 컷·가짜 HUD·사후 합성 공격을 섞지 않는다. 실제 출시 후보 빌드에서 같은
세션을 연속 녹화하고 사용자 입력, actor 준비, 공격 이동, 접촉, target reaction, 환경
복원이 15초 안에 들어가야 한다. 로딩 제거 외의 점프 컷이 필요하면 합격 증빙으로 쓰지
않는다.

`docs/readme/mongroo-emotion-growth-hero.webp`는 기능 증빙 화면이 아니라 README
첫 화면에 사용하는 콘셉트 일러스트다. 실제 기능 설명에는 항상 `screenshots/`
아래의 실행 화면이나 녹화를 사용한다.

32~33번은 2026-08-14 출시 후보를 390×844 모바일 뷰포트에서 실행해 촬영했다.
같은 세션에서 가상 스틱을 실제로 밀어 이동한 전후이며, 캐릭터 자리와 발자국은
합성이 아니라 앱이 그린 것이다.

31번은 2026-08-13 출시 후보의 실제 `SkillBookScreen`을 QA 데이터로 렌더링하고,
Playwright에서 390×844 모바일 뷰포트로 촬영했다. 프리셋·등급·슬롯 제한·잠금
이유를 포함해 화면에 보이는 문구와 조작 상태를 따로 합성하지 않았다.
