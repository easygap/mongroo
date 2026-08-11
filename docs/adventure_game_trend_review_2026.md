# 2026 게임 트렌드 기반 모험·전투 구성 검증

최종 조사: 2026-08-11 KST
상태: 제품 방향·세로 슬라이스·운영 우선순위의 근거 문서
적용 범위: 기본 모험, 수호전, 캐릭터 성장, 스킬 UI, 전투 에셋, 탐험 콘텐츠 운영
상위 불변식: 마음 일기 중심, 감정 비우대, 무손실, 무확률 핵심 성장, 비FOMO

이 문서는 최신 게임의 기능을 모아 붙이는 유행 목록이 아니다. 2026년 시장에서 실제로
확인되는 변화와 최근 출시·운영 중인 게임의 설계 대응을 비교해, 몽그루가 지금 만들어야
할 핵심 경험과 의도적으로 만들지 않을 기능을 결정한다. 타사의 화면·수치·미술·사운드를
복제하지 않고 구조적 원칙만 사용한다.

## 0. 결론

몽그루가 2026년에 경쟁력을 갖는 방법은 대형 수집형 RPG보다 기능·이벤트·캐릭터 수를
더 많이 만드는 것이 아니다. **첫 15초 안에 내가 키운 캐릭터가 고유한 공격을 실제로
날리고, 적이 그 공격을 맞고 반응하며, 감정 성장형과 약점 선택이 결과를 바꾸는 장면**을
완성하는 것이다.

따라서 출시 우선순위는 다음 순서로 고정한다.

1. 하나의 전장에서 3인 파티·적·공격 경로·접촉·피격 반응을 동시에 읽게 한다.
2. 상시 설명을 제거하고 탭은 즉시 명령, 길게 누르기는 전술 상세로 역할을 나눈다.
3. 플레이어와 몬스터 모두 고유한 준비·공격·접촉·반응 스프라이트와 소리를 갖는다.
4. 여섯 마음결은 좋고 나쁨이 없는 전술 속성으로 사용하고, 감정 자체를 피해·붕괴·벌점으로
   만들지 않는다.
5. 한 지역 세로 슬라이스의 재미를 사용자에게 증명한 뒤에만 지역·캐릭터·이벤트 수를 늘린다.
6. 출시 후 콘텐츠는 8~12주 단위의 영구 pack으로 쌓고, 기간 한정 손실·빨간 점·연속 출석으로
   복귀를 강요하지 않는다.

## 1. 조사 방법과 근거 등급

2026-08-11에 공개 접근할 수 있고 게시 주체와 날짜를 확인할 수 있는 자료를 사용했다.
시장 전체 자료는 공개 시차가 있으므로 2026년 7월에 공개된 H1 지표와 5월 월간 순위가
가장 최신인 항목이 있다. 이를 8월 10일 실시간 매출 순위라고 표현하지 않는다. 게임 사례는
7월 공식 업데이트와 8월 4일 출시 자료까지 확인했다.

| 등급 | 자료 | 쓰는 범위 | 한계 |
|---|---|---|---|
| A | 플랫폼·개발사·퍼블리셔의 공식 발표, 패치 노트, 개발자 문답 | 실제 출시 기능, 수정 방향, 플랫폼 원칙 | 흥행 원인을 단독으로 증명하지 못함 |
| B | Sensor Tower·Adjust 등 분석사의 2026 보고서 | 시장 크기, 다운로드·시간·수익·운영 방향 | 추정치와 고객군 편향이 있을 수 있음 |
| C | 표본과 방법을 공개한 플레이어 설문 | 동기·광고 기대·성장 선호의 가설 | 전체 몽그루 사용자를 대표하지 않음 |

- 자료가 말한 사실과 몽그루에 대한 **해석**을 분리한다.
- 단일 성공작의 기능을 시장 표준이라고 부르지 않는다.
- 매출 상위 기능이라도 정서 안전·비FOMO·개발 규모와 충돌하면 채택하지 않는다.
- 커뮤니티 반응은 추가 가설을 찾는 데만 쓰고 이 문서의 확정 근거로 쓰지 않는다.

## 2. 2026 시장 신호와 제품 해석

| 확인한 신호 | 공개 근거 | 몽그루 해석 |
|---|---|---|
| 2026년 상반기 모바일 다운로드는 전년 대비 12% 감소했지만 플레이 시간은 약 2,210억 시간으로 거의 유지되고 IAP도 약 2% 감소에 그쳤다. 광고 노출·지출은 증가했다. | [Sensor Tower H1 2026 Gaming Market Index](https://sensortower.com/blog/h1-2026-digital-gaming-market-index) | 설치 수 경쟁보다 이미 들어온 사용자가 첫 세션에서 약속을 확인하고 다시 오는 경험이 중요하다. |
| 2026 State of Gaming은 다운로드 감소와 수익 유지 속에서 기존 사용자의 유지·참여·수익화 중요성이 커졌다고 정리한다. | [Sensor Tower State of Gaming 2026](https://sensortower.com/report/state-of-gaming-2026) | 콘텐츠 수를 늘리기 전에 첫 전투의 품질과 10판 뒤 변주를 검증한다. |
| Adjust는 2025년 모바일 게임 D1 유지율을 전체 27%, 한국을 20%로 집계하고 2026 핵심을 retention·live ops·cross-platform으로 제시한다. | [Adjust Gaming App Insights 2026](https://www.adjust.com/resources/ebooks/gaming-app-insights/) | 외부 평균을 출시 합격선으로 복사하지 않고, 이탈이 발생한 정확한 장면을 계측한다. |
| RPG는 2025년 약 13.6억 다운로드·98억 달러 매출을 기록했지만 한국 RPG 다운로드는 17%, 매출은 5% 감소했다. 조사 응답자의 69%는 흥미로운 실제 플레이, 47%는 광고와 실제 플레이의 일치를 중요하게 봤다. | [Mistplay Mobile RPG Trends](https://business.mistplay.com/resources/rpg-mobile-game-trends) | 경쟁이 강한 성숙 시장이므로 콘셉트 영상과 실제 전투가 달라서는 안 된다. 상점보다 먼저 진짜 공격 장면을 보여 준다. |
| RPG 응답자는 일반 모바일 게이머보다 성장·힘·사회적 연결 동기가 높고, 의미 있는 진행과 선택을 중시했다. | [Mistplay Mobile RPG Trends](https://business.mistplay.com/resources/rpg-mobile-game-trends) | 레벨 숫자보다 새 스킬, 진화 실루엣, 전투 역할, 관계 기록처럼 보이는 성장을 제공한다. |
| Unity 조사에서 52%의 개발자가 위험을 줄이기 위해 작은 규모 프로젝트를 우선했고 67%는 프로토타입을 3개월 이하로 운영했다. | [Unity 2026 Game Development Report](https://unity.com/blog/2026-unity-game-development-report-trends) | 4지역 전체를 먼저 채우지 않는다. 한 지역·한 파티·한 보스의 완성 세로 슬라이스를 출시 품질로 만든다. |
| 같은 Unity 조사에서 72%가 cross-play를 우선했지만 38%는 기기 간 일관된 UX를 주요 난점으로 꼽았다. | [Unity 2026 Game Development Report](https://unity.com/blog/2026-unity-game-development-report-trends) | 계정 진행과 responsive HUD는 처음부터 분리 설계하되 PC판·동시 멀티플레이는 모바일 세로 슬라이스 뒤로 미룬다. |

시장 수치는 “이 기능을 넣으면 성공한다”는 인과가 아니다. 여기서 확정할 수 있는 것은
획득 비용이 높고 선택지가 많은 시장에서 **첫 약속의 정직성, 반복 가능한 핵심 재미,
지속 가능한 제작 범위**가 더 중요해졌다는 운영 조건이다.

## 3. 최신 게임·플랫폼 사례와 적용 판단

### 3.1 수집형·파티 RPG

| 사례 | 2026년에 확인한 사실 | 몽그루에 적용 | 그대로 쓰지 않음 |
|---|---|---|---|
| Seven Knights Re:BIRTH | Netmarble FY2025 매출 구성에서 15%를 차지했고 PC 확장을 진행했다. 2026년 실시간 결투장은 매 턴 스킬을 직접 고르게 했으며, 합성 Wish는 게이지 도달 시 선택 영웅 획득을 보장했다. | 한 화면의 파티 대치, 짧은 수동 명령, AUTO·배속 보조, 확정 획득·천장처럼 선택을 보호하는 구조 | 영웅 추가 속도, 반복 픽업, 다중 이벤트 통화, PvP 전력 압박 |
| MONGIL: STAR DIVE | 2026-04-15 PC·모바일에 출시해 3인 태그 전투와 몬스터 수집을 전면에 뒀다. 7월 업데이트는 동반자가 실제 전투에 참여하게 하고 반복 전투 파견, 특성 초기화, 일부 합성 성공 보장을 추가했다. | 세 파티원이 초상화가 아니라 전장에 존재하고, 동반자도 고유 행동을 보여 주는 구조. 성장 선택은 무료로 되돌릴 수 있게 함 | 확률 합성, 한정 캐릭터 의존, 7일 선물, 자동 파견이 직접 모험을 대체하는 구조 |
| Arknights: Endfield | 개발팀은 공격·스킬 모션, 전환, 적 피격 반응, 적 예고를 다듬고 고등급 캐릭터별 전용 튜토리얼을 추가했다. 출시 반년 뒤에도 스킬·잠금·보조 타기팅 우선순위를 분리해 개선했다. | 고유 공격만큼 적의 맞는 동작·예고·타기팅 정확도를 출시 gate로 둔다. 캐릭터마다 20~30초 무보상 연습장을 제공한다. | 복잡한 실시간 조작, 높은 등급만 튜토리얼을 받는 차등, 여러 생산 시스템의 동시 도입 |

근거:

- [Netmarble FY2025 Earnings](https://sgimage.netmarble.com/images/netmarble/nmOfficial/20260205/8sto1770273390151.pdf)
- [Seven Knights Re:BIRTH Real Time Arena Update](https://m.netmarble.com/en/news/13423529?pageNo=1)
- [Seven Knights Re:BIRTH Wish Feature](https://ch.netmarble.com/Eng/Newsroom/Detail?bbs_code=1020&post_seq=6706)
- [MONGIL: STAR DIVE Global Launch](https://ch.netmarble.com/Eng/Newsroom/Detail?bbs_code=1020&post_seq=6654&post_tag=MONGIL%3A+STAR+DIVE)
- [MONGIL: STAR DIVE Version 1.2](https://ch.netmarble.com/Eng/Newsroom/Detail?bbs_code=1020&post_seq=6863&post_tag=MONGIL%3A+STAR+DIVE)
- [Arknights: Endfield DEV Comm//02](https://endfield.gryphline.com/en-us/news/1340)
- [Arknights: Endfield Homecoming DEV Comm](https://endfield.gryphline.com/en-us/news/7017)

### 3.2 전투 흐름·촉각·감정 규칙

| 사례 | 2026년에 확인한 사실 | 몽그루에 적용 | 그대로 쓰지 않음 |
|---|---|---|---|
| Beast of Reincarnation | 2026-08-04 출시작으로 실시간 검격과 동료 명령을 결합한다. 명령 메뉴를 열면 시간이 느려져 전장을 읽고 기술을 고를 수 있다. | 반사신경을 요구하지 않으면서 화면 흐름을 끊지 않는 `전술 집중` 상태. 길게 누르는 동안 불필요한 움직임을 줄이고 대상·경로·상성을 강조 | 패링 난도, 실시간 액션 축소판, 어두운 멸망 서사 |
| The Seven Deadly Sins: Origin | 캐릭터 전환·연계·궁극기·피격에 서로 다른 진동을 쓰고 무기와 스킬 개념에 따라 촉각 패턴을 구분한다. | 기본 공격·고유기·방어·약점 접촉·피격·풀려남을 서로 다른 짧은 햅틱 어휘로 만든다. 소리·시각에도 같은 사건 ID를 사용 | 강한 진동의 상시 사용, 콘솔 입력 압력 기믹, 4인 액션 조작 |
| Chaos Zero Nightmare | 스토어 설명은 스트레스·붕괴, 카드 선택, 분기, run마다 바뀌는 저장 데이터를 핵심으로 내세운다. | 감정이 외형만이 아니라 선택·상성·스킬 family를 바꾸고, run 선택이 기록에 남는다는 구조적 아이디어 | 슬픔·불안·분노를 스트레스 피해나 정신 붕괴로 처벌하는 표현, 일기 내용으로 전투 난도를 올리는 처리 |

근거:

- [PlayStation Blog — Beast of Reincarnation](https://blog.playstation.com/2026/02/12/beast-of-reincarnation-launches-on-ps5-august-4-2026/)
- [PlayStation Blog — The Seven Deadly Sins: Origin](https://blog.playstation.com/2026/03/13/the-seven-deadly-sins-origin-ps5-features-detailed-launches-march-16/)
- [Google Play — Chaos Zero Nightmare](https://play.google.com/store/apps/details?hl=en-US&id=com.smilegate.chaoszero.stove.google)

### 3.3 모바일 상호작용과 시청각 완성도

- Google Play는 2025 Best Game으로 Pokémon TCG Pocket을 선정하며 카드 개봉과 감상의
  촉각적인 상호작용을 강조했다. 몽그루에서는 스킬 아이콘 누름, 공격 준비, 접촉, 도감
  흡수에 각각 손가락으로 느껴지는 짧은 반응을 둔다.
- Apple의 2026 Design Awards는 읽기보다 탐색에 집중하게 하는 직관적 조작, 모션·감각
  피드백 조절, 한 주제 안에서 통일된 애니메이션을 높게 평가했다. Arknights: Endfield도
  Visuals and Graphics finalist에 포함됐다.
- Apple 게임 개발 지침은 터치 중심 조작과 중요한 사건의 햅틱을, 접근성 지침은 소리
  신호를 시각·촉각 신호와 함께 제공하는 것을 권한다.

근거:

- [Google Play Best of 2025](https://blog.google/products-and-platforms/platforms/google-play/best-apps-games-2025/)
- [Apple Design Awards 2026](https://www.apple.com/uk/newsroom/2026/06/apple-reveals-winners-of-the-2026-apple-design-awards/)
- [Apple Developer — Games](https://developer.apple.com/games/get-started/)
- [Apple Human Interface Guidelines — Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility/)

### 3.4 8월 11일 전투 연출 재검증

| 최신 확인 내용 | 설계에 반영한 기준 | 이번 구현 |
|---|---|---|
| Arknights: Endfield는 공격·스킬 모션, 적 피격 반응, 적 공격 준비 예고를 각각 개선했고 2026-07-11 업데이트에서는 스킬 타기팅·잠금·보조 선택 우선순위를 분리했다. | 공격 원화의 화려함과 별개로 `누가 맞는가`, `언제 닿는가`, `맞은 뒤 무엇이 변하는가`를 독립 출시 gate로 둔다. | 세 번째 전용 적 공격을 `lowest` 계약으로 만들고 실제 최저 체력 대원 이벤트까지 회귀 테스트한다. |
| Riot의 VFX 가독성 원칙은 투사체가 정지 화면에서도 진행 방향을 보여야 하고, 효과 크기는 실제 전술 중요도와 맞아야 하며, 불필요한 시각 소음을 줄여야 한다고 정리한다. | 단일 대상 위력 1 공격은 화면을 덮는 폭발 대신 방향성이 강한 작은 본체와 제한된 접촉 반응을 쓴다. | `꽃잎 살촉`을 왼쪽 삼각형 실루엣, 작은 접촉 별, 제한된 꽃잎 파편으로 제작한다. |
| Apple 접근성 선언은 핵심 정보를 색 외의 모양·문자로도 구분하고, Reduced Motion에서도 의미 있는 상태 변화는 제거하지 말고 정지 강조·fade 등으로 보존하도록 요구한다. | `front/all/lowest`는 색을 공유해도 각각 `겹화살표/동심원/조준점` 형태와 텍스트를 함께 쓴다. 저감 모션은 맥동만 멈추고 형태와 접촉 프레임을 남긴다. | 전투 무대 painter와 두 지휘 UI가 같은 target 형태 함수를 사용하고 VoiceOver용 대상 문구를 유지한다. |

근거:

- [Arknights: Endfield DEV Comm//02](https://endfield.gryphline.com/en-us/news/1340)
- [Arknights: Endfield Homecoming DEV Comm](https://endfield.gryphline.com/en-us/news/7017)
- [Riot Games — Clarity in League](https://www.leagueoflegends.com/en-us/news/dev/clarity-in-league/)
- [Apple — Accessibility declarations](https://developer.apple.com/documentation/appstoreconnectapi/configuring-accessibility-declarations)
- [Apple — Reduced Motion evaluation criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/reduced-motion-evaluation-criteria)

## 4. 몽그루의 2026 목표 구성

### 4.1 제품 위치

몽그루 탐험은 대형 오픈월드나 경쟁형 수집 RPG가 아니라 **일기에서 자란 캐릭터와
짧게 떠나는 따뜻한 전술 수집 RPG**다.

- 수집 이유: 높은 전력만이 아니라 고유 공격, 감정 성장형, 관계 반응, 발견 방식이 다르다.
- 전투 이유: 적을 죽이는 것이 아니라 엉킴을 풀고 장소의 기능과 빛을 되돌린다.
- 반복 이유: 놓칠 보상 때문이 아니라 다른 파티·상성·관계·미관찰 기록이 남아 있다.
- 차별점: 사용자가 남긴 마음은 캐릭터의 결을 만들지만 좋은 감정·나쁜 감정으로 채점되지
  않는다.

### 4.2 세션 층

| 층 | 시간 | 화면 구조 | 목적 |
|---|---:|---|---|
| 기본 스테이지 | 1~3분 | 같은 무대의 접근→조우→전투/사건→풀려남→전진 | 짧은 전투 손맛과 명확한 진행 |
| 지역 battle trail | 8스테이지, 총 10~15분 | 각 점에서 저장되며 원하면 연속 재생 | 전투·사건·쉼터·보스의 한 장 리듬 |
| 깊은 조사 | 8~15분 | 지역 완주 뒤 선택형 노드 지도 | 경로 탐색·기록서·장기 선택 |
| 자동 순찰 | 백그라운드 | 허브 하위 진입점 | 바쁜 날의 보조 수집, 직접 모험 대체 금지 |

일반 스테이지 사이에 지도·정보 시트·로딩·결과 페이지를 강제로 끼우지 않는다. 서버는
스테이지마다 저장하지만 사용자는 한 지역의 같은 카메라와 BGM이 이어진다고 느껴야 한다.

### 4.3 한 화면의 정보 계층

1. 화면 중앙 72~78%는 전장과 공격 경로다.
2. 상단 가장자리는 8점 진행 rail, 현재 wave·round, 적 의도만 가진다.
3. 하단은 파티 초상 3개와 활성 대원의 6아이콘 벨트다.
4. AUTO·배속·짧은 연출·일시정지는 모서리에 두고 전장을 불투명 카드로 덮지 않는다.
5. 탭은 즉시 선택·실행하고, 350ms 길게 누르면 `전술 집중`이 열린다.
6. `전술 집중` 중에는 비핵심 ambient motion을 멈추고 시전자→공격 경로→대상, 현재
   약점·내성, 비용·효과만 강조한다. 상세 시트는 화면 높이 40%를 넘지 않는다.
7. 12초 동안 입력이 없으면 합법 행동 하나만 한 번 맥동한다. 자동 선택·자원 소비·대사
   팝업은 발생하지 않는다.

### 4.4 전투 문법

- 첫 재도전은 허브 탭 뒤 3초 안에 명령 가능, 신규 사용자는 15초 안에 첫 공격이 대상에
  접촉해야 한다.
- 한 행동은 `입력 반응→actor 준비→공격 본체 이동→접촉→대상 반응→수치/상태→복귀`로
  이어진다. 로그나 파티클만으로 결과를 먼저 알리지 않는다.
- 같은 순간의 주요 시선 사건은 주 공격 1, 대상 반응 1, 환경 accent 1을 넘지 않는다.
- 파티 3명은 전장에 남는다. 행동하지 않는 대원도 시선·호흡·짧은 보조 반응으로 현재
  사건을 따라가되 주 공격을 가리지 않는다.
- 적도 플레이어와 같은 품질 gate를 통과한다. 예고 pose·실제 공격 본체·접촉·방어/피격
  반응·고유 SFX가 없는 적은 출시할 수 없다.
- 전술에 필요한 의도·대상·약점·내성은 첫 조우부터 보인다. 생태·스킬 전문·히든 보상은
  관찰과 획득 뒤 도서관에서 연다.

### 4.5 감정 성장·상성·캐릭터 가치

- 여섯 마음결은 동등한 속성이다. 어느 결도 공격력·획득률·희귀도에서 유리하지 않다.
- stage 3 주결, stage 4 보조결 해금은 현재 성장 계약을 유지한다. 특정 스킬을 얻으려고
  특정 감정의 일기를 쓰라고 권하지 않는다.
- 몬스터는 고정 약점 1·내성 1을 갖고, 조합 전체에서 여섯 결의 등장 수와 승률을 맞춘다.
- 감정은 선택과 전투 표현을 바꾸지만 스트레스·붕괴·부상·성장 실패의 원인이 아니다.
- 비싼 캐릭터는 고유 실루엣·애니메이션·음향·장기 성장 상한과 역할 완성도가 더 높을 수
  있지만 필수 콘텐츠 독점, 절대 상위 스킬, 감정별 과금 우위는 만들지 않는다. 정확한
  계수와 상한은 `character_skill_growth_design.md`만 결정한다.
- 모든 캐릭터는 획득 전후에 20~30초 연습장에서 고유 I·II, 역할, 대표 접촉 연출을 직접
  시험할 수 있다. 연습은 보상·입장권·일일 횟수가 없다.

### 4.6 오디오·햅틱

| 사건 | 소리 | 햅틱 | 시각 대체 |
|---|---|---|---|
| 아이콘 선택 | 재질별 짧은 준비음 | 10~18ms light | 테두리 수축·복원 |
| 공격 접촉 | family contact + 대상 재질 | 18~35ms medium | 접촉점 ring + hit pose |
| 약점 적중 | 접촉음 뒤 짧은 배음 | 2회 분리 pulse | 약점 glyph 한 번 확장 |
| 마음 지키기 | 공격음→방패 재질음 | 단단한 단일 pulse | 방패 변형·피해 차단 |
| 풀려남 | 지역 cadence | 부드러운 상승 1회 | 원래 물건 복원·환경 점등 |

오디오·햅틱을 끈 사용자도 판정을 모두 읽을 수 있어야 한다. 모션 감소는 이동량·shake를
줄이되 접촉 순서와 상태 변화는 유지한다.

### 4.7 라이브 운영

2026 상위 모바일 게임은 연계 이벤트와 시즌 업데이트로 참여를 유지하지만, 이벤트 수가
많다는 사실만으로 지속 성과가 보장되지는 않는다. 몽그루는 다음처럼 번역한다.

- 첫 세로 슬라이스가 사용자 합격선을 통과하기 전에는 live ops를 만들지 않는다.
- 영구 콘텐츠 pack은 8~12주 간격을 기본으로 한다. 일정이 부족하면 수량을 줄인다.
- 계절 기간에는 허브 장식·지역 조명·추천 순서만 바꿀 수 있다. 이야기·스킬북·캐릭터는
  기간 뒤에도 같은 조건으로 남는다.
- 동시에 전면 노출하는 모험 목표는 하나다. 여러 이벤트 통화·패스·출석판을 겹치지 않는다.
- milestone은 이미 한 일기·전투·발견을 묶어 보여 줄 뿐 추가 반복을 요구하지 않는다.
- 새 pack은 새 수치층보다 적 행동 조합, 파티 관계 beat, 환경 변화, 도감 기록을 늘린다.

근거: [Sensor Tower — Winning with Live Ops](https://sensortower.com/blog/top-grossing-mobile-games-live-ops-strategies-2025-report),
[Sensor Tower — May 2026 Top Mobile Games](https://sensortower.com/blog/top-10-worldwide-mobile-games-by-revenue-and-downloads-in-may-2026).

### 4.8 광고·스토어·공유 화면의 정직성

- 스토어 첫 동영상은 실제 빌드의 `actor 준비→공격 이동→접촉→적 반응→환경 복원`을
  15초 안에 보여 준다.
- ImageGen 콘셉트는 개발 문서와 제작 기준으로만 사용한다. 스토어 gameplay 표기 영역에
  합성 콘셉트를 실제 플레이처럼 넣지 않는다.
- 스토어 스크린샷의 HUD, 아이콘 수, 파티 수, 약점 표시가 출시 빌드와 같아야 한다.
- 일기 원문·감정 라벨을 광고 개인화, 공유 카드, 리플레이 파일명에 사용하지 않는다.

## 5. 채택·실험·보류·배제

| 상태 | 결정 |
|---|---|
| 지금 채택 | 통합 전장, 8점 trail, 3인 전장 존재감, 6아이콘 벨트, 실제 공격·피격 시퀀스, 감정 상성, 적별 예고·공격, 길게 누르기 상세, 고유 오디오·햅틱, 영구 pack |
| 세로 슬라이스 실험 | 12초 무입력 힌트, 350ms 전술 집중, 15초 실제 gameplay 공유 클립, 캐릭터별 20~30초 연습장 |
| 모바일 검증 뒤 보류 | PC 클라이언트, cross-save UI, 친구 정원 비동기 방문, 협동 수호전 |
| 배제 | 실시간 PvP, 길드 의무, 배틀패스, 기간 한정 전력, 확률 스킬북, 감정 붕괴 게이지, 자동 전투 전용 성장, 이벤트 통화 중첩, 빨간 점·countdown |

## 6. 한 지역 세로 슬라이스

2026 조사에서 가장 중요한 제작 결정은 전체 콘텐츠보다 아래 한 판을 먼저 완성하는 것이다.

### 6.1 범위

- 기억서고 스테이지 1~4와 스테이지 8 수호자 1회
- 실제 파티 3명, 각자 고유 I·II 중 대표 공격 최소 1종
- 일반 엉킴 2종·큰 엉킴 1종, 적별 기본 공격과 큰 엉킴 추가 공격
- 약점·내성 두 결 이상, 마음 지키기, 풀려남, 환경 복원
- adaptive BGM 1지역, 플레이어·적 contact, guard, release, 햅틱
- 실제 ImageGen 원본을 단계별 제작·수작업 정리한 투명 스프라이트

### 6.2 출시 전 합격선

| 항목 | 합격선 |
|---|---:|
| 재도전 허브→명령 가능 | p95 3초 이하 |
| 신규 사용자 허브→첫 실제 접촉 | p95 15초 이하 |
| 첫 전투 스테이지 | 중앙값 60~120초 |
| 첫 판 자력 완주 | 전체 85% 이상, 핵심 사용자군별 80% 이상 |
| 공격이 실제로 날아가 닿았다고 응답 | 90% 이상 |
| 공격 주체·대상·약점·적 의도 식별 | 각 90% 이상 |
| 5분 뒤 공격/풀려남/환경 변화 중 하나 자유 회상 | 75% 이상 |
| 소리 없이 판정 이해 | 95% 이상 |
| 화면 없이 소리로 contact·guard·release 구분 | 80% 이상 |
| 10판 뒤 재미 | 중앙값 5.5/7 이상 |
| production placeholder·공용 enemy attack | 0건 |

이 표를 통과하기 전에는 지역 2~4의 공격 family나 live ops 수량을 늘리지 않는다. 실패하면
보상·숫자·튜토리얼 문장을 더하기 전에 공격 인과, 카메라, 타기팅, 아이콘 위치, 적 예고를
수정한다.

## 7. 계측과 개인정보

필수 사건은 `adventure_resume`, `command_ready`, `skill_press`, `skill_hold`,
`target_confirm`, `attack_release`, `attack_contact`, `target_reaction`, `intent_shown`,
`hint_pulse`, `stage_release`, `advance_ready`, `stage_exit`이다.

- 모두 익명 사용자·세션·content version·기기 등급·timestamp·skill/enemy code만 가진다.
- 일기 원문, 감정 문장, 감정 점수, 안전 분류, 자유 입력을 넣지 않는다.
- `release→contact`, `contact→reaction`, `resume→command_ready`, `idle→hint`를 계산해
  연출과 입력 병목을 구분한다.
- D1·D7은 전체 앱 복귀와 모험 복귀를 나눠 본다. 모험 반복을 늘리려고 일기 경험을
  약화시키지 않는다.

## 8. 재검토 주기

- 월 1회: 국내·글로벌 RPG 상위 변동과 주요 업데이트를 관찰하되 문서를 자동 변경하지 않는다.
- 분기 1회: 이 문서의 시장 수치·출처·경쟁작 상태를 갱신하고 제품 가설별 실제 지표를 붙인다.
- 업데이트 직후: 경쟁작 기능이 아니라 우리 사용자의 이탈·회상·이해 데이터를 우선한다.
- 두 분기 연속 근거가 없거나 사용자 실험에서 실패한 트렌드 항목은 삭제한다.

다음 재검토 예정일은 2026-11-10이다. 재검토일까지도 이 문서보다
`expedition_stage_redesign.md`의 화면 계약, `character_skill_growth_design.md`의 수치 계약,
`EXPEDITION_ASSET_PRODUCTION.md`의 제작 gate가 구현의 직접 원본이다.
