# 수호짐승 보스 패턴 VFX v9

상태: **production candidate — 실기 프로파일·최종 아트 승인 전**

돌비늘 장부지기의 2·3페이즈가 공용 파동을 반복하지 않도록 `뿌리 봉쇄진`과
`최종 말소선`을 각각 8프레임 전용 공격으로 제작했다. 두 공격은 같은 보스에
속하지만 실루엣과 파훼법이 다르다.

| family | 서사·기믹 | 실루엣 | 파훼 |
|---|---|---|---|
| `guardian.root-lockdown` | 붉은 뿌리가 전열을 봉쇄 | 세 갈래 뿌리 → 격자 | 한 명 이상 마음 지키기 |
| `guardian.final-redaction` | 장부의 마지막 교정선이 기록을 지움 | 단일 먹선 → 이중선 → X | 라운드마다 약점 적중 |

## Imagegen 생성 기록

- 모드: 내장 Imagegen, 신규 이미지 2회. 기존 이미지를 수정하지 않았다.
- 스타일 참조: `ledger-claw-v2`, `boss-phase-break-v1`, `paper-flurry-v1`의
  따뜻한 동화책 재질, 선 밀도, 밝은/어두운 배경 QA 문법만 참조했다.
- 공통 제약: 1536×1024, 2×4, 오른쪽→왼쪽, 캐릭터·몬스터·배경·UI·문자 제외,
  셀 밖 침범 금지, 완전 균일 `#00FFFF` 크로마 배경.
- `root-lockdown` 프롬프트 핵심: 붉은 갈색 기록 뿌리, 희미한 금빛 색인 문양,
  조임→세 갈래 방출→삼각 봉쇄→격자 접촉→회수.
- `final-redaction` 프롬프트 핵심: 먹빛 교정선, 찢긴 크림색 장부 종이,
  보랏빛·금빛 색인 봉인, 단일선→이중선→X 접촉→종이 파쇄→회수.
- 원본: 각 family의 `sources/*-sheet-chroma.png`
- 프로젝트 원본:
  - `root-lockdown/sources/root_lockdown-sheet-chroma.png`
  - `final-redaction/sources/final_redaction-sheet-chroma.png`
- 알파 마스터: 각 family의 `alpha/frame-*.png`

## 알파·런타임·블렌딩

`design-system/scripts/build_boss_pattern_assets.py`가 크로마 제거, 전경색 dilation,
셀 구분선 제거, 576×288 정규화, WebP 내보내기, SHA-256, 밝은/어두운 QA와
애니메이션 미리보기를 한 번에 만든다.

- 런타임: `app/assets/adventure/effects/root-lockdown-v1`,
  `app/assets/adventure/effects/final-redaction-v1`
- 각 8프레임, 총 16프레임, contact frame 4
- 프레임 합계 800ms. 서버 `cast/channel` 예고 흐름 안에서 접촉 시점만 manifest로
  고정하고 저감 모션에서도 같은 정지 실루엣을 쓴다.
- `production_ready:false`: 저사양 Android/iOS p95, 320/390/430dp 접촉 위치,
  밝은/어두운 실전 배경의 잔여 크로마 검수 뒤에만 승격한다.
