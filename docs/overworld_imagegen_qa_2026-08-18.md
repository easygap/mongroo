# 오버월드 ImageGen 실험·탈락 기록 (2026-08-18)

## 실행 방식

- 모드: Codex 내장 ImageGen (`stylized-concept`, 투명화 편집은
  `background-extraction`)
- 용도: 이끼 기억서고 타일/조형물의 색·덩어리·재질 방향 탐색
- 런타임 채택 이미지: **0개**
- 이유: 바닥은 반복 경계를 출시 수준으로 증명하지 못했고, 조형물은 투명 배경
  요청과 재편집 뒤에도 실제 알파가 아닌 체크무늬가 구워진 `rgb24`였다.
  체크무늬 제거 후처리로 가장자리를 훼손하지 않고, 전부 앱 에셋에서 제외했다.

## 공통 프롬프트 불변식

```text
clean high-resolution hand-authored 2D game art
top-down or 3/4 top-down orthographic game asset
broad contiguous color shapes, limited palette, crisp intentional silhouette
readable at 64x64 / 96x96 / 128x128
soft upper-left key, restrained ambient occlusion, localized glow only

Avoid: stippling, pointillism, dithering, grain, film noise, speckles,
random brush dots, micro-detail clutter, painterly impasto, watercolor bloom,
photorealistic scan texture, over-sharpening, generative texture mush,
AI artifact clusters, excessive detail.
```

## 자산별 최종 프롬프트 세트

1. `ground-flagstone`: 사방 이음매가 없는 따뜻한 회갈색 기록서고 판석 바닥,
   6~10개의 큰 판석, 얕은 베벨, 홈 모서리의 극소량 이끼, 강한 방향광 없음.
2. `ground-moss`: 사방 이음매가 없는 부드러운 이끼 바닥, 큰 이끼 쿠션과 적은
   흙 노출, 중심 랜드마크/꽃/돌/낙엽 없음.
3. `ground-water`: 사방 이음매가 없는 얕은 청록 물, 5~8개의 큰 곡선 물결,
   미세 물결/스파클/고주파 카우스틱 없음.
4. `wall-archive`: 한 타일 너비의 수평 기록벽, 좁은 상판과 전면, 5~7개 큰
   석재 블록, 황동 인레이, 모듈 결합 가능한 양 끝.
5. `chest-archive`: 닫힌 호두나무 상자 하나, 황동 테두리와 명확한 잠금장치,
   올리브 천 띠와 작은 청록 기억 유리.
6. `lantern-archive`: 팔각 청록 유리의 황동 등불 기둥 하나, 원형 석재 받침,
   유리 가까이에만 제한한 발광.
7. `shelf-ruined`: 두 단의 낮고 튼튼한 서가 하나, 부서진 위 모서리, 책은
   8~12개의 큰 색 덩어리, 낱권 미세 묘사 없음.
8. `altar-record`: 두 단 석재 제단, 황동 받침의 닫힌 기억책 한 권, 앞면 청록
   렌즈, 책 틈과 렌즈에만 좁은 발광.
9. `alpha-extraction`: 입력 조형물은 모양·색·자세·조명·접촉 그림자를 그대로
   보존하고 흰색/연회색 체크무늬 배경만 실제 투명 알파로 교체. 흰 테두리·매트·
   새 배경·형태 변경 금지. 결과 파일 채널이 계속 `rgb24`여서 탈락.

## 런타임 대체와 아틀라스 승격

위 콘셉트에서는 넓은 색면·회갈색 돌·올리브 이끼·황동·국소 청록광만 가져왔다.
ImageGen 비트맵은 한 장도 런타임에 넣지 않았다. 대신
`design-system/scripts/build_expedition_tile_atlas.py`가 점·입자·난수·디더링 없이
96px 셀을 결정적으로 그려 다음 산출물을 만든다.

- `expedition-tile-atlas-v1.png`: 800×1200 RGBA, 27,672바이트, 4지역 × 21종 셀
- `expedition-tile-atlas-v1.json`: 96px 셀·2px 압출 거터·100px stride의 좌표와
  지역 매니페스트
- 종류: 바닥 4, 이끼 2, 물 2, 해안 N/E/S/W, 벽·서가·등불·상자·아이템·NPC·
  몬스터·제단·뿌리 9

`--check`는 메모리에서 다시 만든 PNG와 매니페스트를 바이트 단위로 비교한다.
런타임은 한 장을 한 번 디코드하고, 화면에 보이는 바닥만 `drawAtlas`로 일괄
그린다. 조형물은 같은 아틀라스의 셀을 발밑 앵커에 배치하고 Y 좌표로 깊이를
정렬한다. 디코드 실패 때만 기존 결정적 캔버스 도형으로 물러나므로 손상된
개발 번들에서도 이동 자체는 막히지 않는다.

## AI-slop 방지 자동 관문

- LANCZOS 재표본화에서 생기던 링잉·가색 픽셀을 없애고 `nearest`로 고정했다.
- 바닥·이끼·물은 알파 최솟값 255인 완전 불투명 셀만 허용한다. 명암은 반투명
  점이 아니라 저대비 불투명 색 혼합으로 만든다.
- 생성기는 각 셀의 불투명 이웃 간 고주파 경계 비율과 고립 점 비율을 계산한다.
  현재 최댓값은 각각 0.102403, 0.000551이며 한계 0.18, 0.001을 넘으면 빌드가
  실패한다. 바닥·이끼·물 셀의 고주파 비율은 모두 0이다.
- 셀마다 2px 가장자리 픽셀을 바깥으로 압출해 이동·축소·선형 샘플링 중 이웃
  셀이 새거나 검은 선이 생기지 않게 했다.
- 첫 실구동본에서 반투명 바닥 명암 때문에 어두운 격자가 비치는 것을 발견해
  불합격 처리했고, 완전 불투명 저대비 면으로 교체한 두 번째 실구동본만 채택했다.

## 청크·레이어 런타임

- 42×30의 지형 값은 충돌과 경로 탐색을 위한 작은 논리 데이터로 유지하되,
  렌더·오브젝트 조회는 8×8 청크 24개로 나눈다.
- 각 청크는 `staticScenery`, `interactables`, `actors`를 별도 목록으로 보유한다.
  벽·서가·등불·뿌리, 상자·아이템·제단, NPC·몬스터가 서로 다른 레이어다.
- 지면 셀은 변형 번호와 네 방향 해안 마스크를 한 번만 계산한다. 매 프레임에는
  카메라와 겹치는 청크의 셀만 `drawAtlas`로 보낸다.
- 미니맵의 정적 지형·조형물은 `ui.Picture`로 한 번 기록하고, 프레임마다 카메라
  사각형과 플레이어 점만 다시 그린다.
- 실브라우저에서 실제 보행 중 209타일·6청크에서 260타일·9청크로 전환되는 것,
  물 충돌과 가장자리 슬라이딩, 카메라·미니맵 추종, 목적지→전투 전환을 확인했다.

## 2D 리토폴로지 규칙

- 보이는 외곽(`visualBounds`)과 발밑 충돌 외곽(`collisionBounds`)을 분리한다.
- 물은 사각 이미지가 아니라 셀 지형이며, 인접 네 방향으로 해안 오버레이를
  자동 선택한다.
- 플레이어는 반지름 0.28타일의 원형 발자국을 9점으로 샘플링한다.
- 한 프레임의 이동을 최대 0.12타일로 나눠 터널링을 막고 X/Y 축을 따로 풀어
  벽을 자연스럽게 따라 미끄러지게 한다.
- 4지역×8스테이지의 출발점→제단 연결성을 BFS 회귀 테스트로 고정한다.
