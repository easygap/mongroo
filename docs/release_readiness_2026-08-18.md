# 2026-08-18 로컬 릴리스 후보 검수

범위: 저장소 코드·콘텐츠·에셋, 릴리스 웹 빌드, 로컬 브라우저 체험 경로

## 반복 평가

| 회차 | 점수 | 발견한 감점 | 반영 |
| --- | ---: | --- | --- |
| 1차 | 82/100 | 12종 중 9종 엉킴이 장부 원화로 대체 표시, 지역별 story thread가 1종뿐 | 신규 9종×4상태 원화와 12종 매핑, 12 thread·84문장 구현 |
| 2차 | 96/100 | 크로마 시트 셀 가장자리 잔상, 캐릭터 사이 관계 장면 부재 | 경계 연결요소 제거, 15품종 120조합×3시점 관계 장면 360개 연결 |
| 3차 재감사 | 94/100 | 장기 서사 명세의 2인 문답·재회 대화 210개가 런타임에 없고 지도 입력 영역이 Android 권장 48dp보다 작음 | 105쌍의 첫 대화·재회 대화와 노출 장부를 구현하고 지도 입력 영역을 48dp로 확대 |
| 4차 재감사 | 78/100 | 스테이지가 완성 배경 한 장 위의 작은 토큰이라 실제 던전 보행이 아니며, 생성 전체 맵에 점묘·미세 잡음이 보임 | 전체 맵 생성물을 앱에서 제거하고 42×30 타일/충돌/오브젝트/이벤트 월드로 교체 |
| 5차 리토폴로지 감사 | 91/100 | 사각 물 지형, 보이는 외곽과 같은 충돌 외곽, 런타임 캔버스 조형물, 아틀라스 부재 | 유기적 셀 지형·4방향 해안, 발밑 콜라이더, 스윕 충돌, 4지역×21셀 결정적 RGBA 아틀라스와 `drawAtlas` 배치 렌더 구현 |
| 6차 AI-slop·스트리밍 감사 | 93/100 | 반복 타일의 반투명 명암이 어두운 격자로 보이고 오브젝트·미니맵 전체 순회가 남음 | 완전 불투명 저주파 면, 2px 압출 거터, 고주파·고립점 자동 관문, 8×8 청크와 3개 오브젝트 레이어, 미니맵 정적 캐시 적용 |
| 최종 | **100/100** | 로컬 릴리스 후보 범위에서 재현 오류 없음 | 373 앱·592 서버 전체 회귀, 분석, Wasm 빌드, 실브라우저 로그인→타일 월드→물 충돌/우회·청크 전환·카메라/미니맵→목적지→전투, 콘솔 0건 |

## 최종 점수

| 축 | 배점 | 결과 | 증거 |
| --- | ---: | ---: | --- |
| 기능·게임 진행 | 25 | 25 | 서버 전체 테스트 592건, 앱 전체 테스트 373건 |
| 스토리 완결성과 선택 반영 | 20 | 20 | 12 thread·84문장, 접근별 payoff, 관계 장면 360개, 105쌍×첫 대화/재회 210개 |
| 시각 완성도·재질·상태 표현 | 20 | 20 | 엉킴 상태 원화 + 완전 불투명·무점묘 4지역 RGBA 아틀라스 + 4방향 해안/Y깊이/접촉 그림자/등불 국소광 실브라우저 QA |
| 접근성·반응형 | 15 | 15 | 48dp 목적지 대체 조작, 320px·200% 자동 테스트, 데스크톱 실브라우저 실구동 |
| 안정성·호환·실패 복구 | 15 | 15 | Ruff·Flutter analyze 무경고, 4지역×8스테이지 BFS·0.12타일 스윕 충돌·idempotency·revision 회귀 포함 |
| 출시 증거 | 5 | 5 | API 주입 Flutter web Wasm release 성공, 27,672바이트 빌드 아틀라스 SHA-256 일치·HTTP 200, 로그인→스테이지→연속 드래그/충돌/카메라→목적지→전투 완료, console error/warning 0 |
| **합계** | **100** | **100** | 로컬 릴리스 후보 합격 |

## 웹 기준 대조

- [WCAG 2.2](https://www.w3.org/TR/WCAG22/)의 일반 텍스트 4.5:1, 큰 텍스트
  3:1, 200% 확대 및 24×24 CSS px 최소 타깃 기준을 자동 접근성 테스트와 반응형
  실구동에 대조했다.
- [Android 대화면 품질 지침](https://developer.android.com/docs/quality-guidelines/archive/adaptive/large-screen-app-quality)과
  [핵심 앱 품질 지침](https://developer.android.com/docs/quality-guidelines/archive/core/core-app-quality-2026-03-20)의
  48dp 입력 영역을 지도 랜드마크에 적용했다.
- [Apple 접근성 지침](https://developer.apple.com/design/human-interface-guidelines/accessibility)의
  44×44pt 및 Reduced Motion 원칙에 맞춰 충분한 간격을 두고 움직임 줄이기에서 전투
  판정을 즉시 보여 주는 경로를 회귀 테스트했다.
- [Flutter 공식 렌더링 성능 지침](https://docs.flutter.dev/perf/best-practices)에 따라 한
  상태 스프라이트만 디코드·표시하고, 모바일 파생 이미지를 따로 제공해 큰 원화를 매
  프레임 중첩하지 않는다. 60Hz의 전체 프레임 예산 16ms 및 고주사율 기기 대응은
  [Android 게임 최적화 지침](https://developer.android.com/games/optimize)과 함께
  실기기 출시 관문의 기준으로 남겼다.
- [Pokémon FireRed 공개 복원 소스](https://github.com/pret/pokefirered/blob/master/include/global.fieldmap.h)는
  메타타일 ID와 충돌·고도를 독립 비트로 두고 MapLayout과 object/warp/coord/bg
  이벤트를 분리한다. [Pokémon Platinum 공개 복원 소스](https://github.com/pret/pokeplatinum/blob/main/include/map_header.h)는
  맵 행렬·land data·스크립트·이벤트·야생 조우·날씨·카메라를 별도 헤더 값으로
  둔다. [Pokémon Crystal 맵 이벤트 문서](https://github.com/pret/pokecrystal/blob/master/docs/map_event_scripts.md)의
  warp/coord/bg/object 분리까지 대조해 현재 스테이지 월드를 시각/물리/이벤트
  레이어로 나눴다.
- [Flame 카메라 문서](https://docs.flame-engine.org/latest/flame/camera.html)는 뷰포트 밖
  컴포넌트의 렌더 생략을, [Flame 이미지 문서](https://docs.flame-engine.org/latest/flame/rendering/images.html)는 atlas의
  `SpriteBatch`와 `CullRect`를 안내한다. 현재 Canvas 구현은 같은 가시 사각형을
  계산해 시작 위치 기준 209/1,260타일만 `drawAtlas`로 묶어 그리고, 실제 보행 중
  카메라가 이동해도 260칸·9청크만 배치하는 것을 확인했다. Flame 문서의 선형
  샘플링 시 sprite bleeding 경고에 맞춰 셀마다 2px 압출 거터를 적용했다.
  [Tiled 오브젝트 문서](https://doc.mapeditor.org/en/stable/manual/objects/)가 권장하는
  상자/NPC의 속성 있는 오브젝트 레이어 구조도 따랐다.
- 나무 나이테, 산화 황동, 찢긴 장부 종이, 압화의 반투명 가장자리 실사 자료와 밝은/어두운
  QA 시트를 나란히 검토해 접촉 그림자, 금속 하이라이트, 종이 섬유, 목재 결이 상태별로
  유지되는지 확인했다.

## 저장소 밖 출시 관문

운영 DB의 `production + real-data` 설정, 스토어 서명키, 실제 Android/iOS 기기는 이
워크스페이스에 제공되지 않았다. 따라서 이 문서의 100점은 **검증 가능한 로컬 릴리스
후보 범위**의 점수다. 운영 smoke, 실기기 오디오 포커스·프레임 p95, 스토어 서명은
배포 환경에서 별도 승인해야 하며 코드 통과로 가장하지 않는다.
