# 꽃잎 살촉 VFX v6

상태: **production candidate — 실기 프로파일·최종 아트 승인 전**

표류 압화 떼의 `꽃잎 살촉`을 오른쪽에서 왼쪽으로 날아가 최저 체력 대원 한 명을
정확히 겨누는 7프레임 공격으로 제작했다. 압화의 따뜻한 재질은 유지하되, 정지 화면만
보아도 진행 방향과 접촉점을 알 수 있도록 긴 삼각형 실루엣과 작은 접촉 별을 사용했다.
광역 스킬처럼 보이지 않도록 충격 범위와 파편 수는 의도적으로 제한했다.

## 프레임 구성

| 프레임 | 구간 | 시간 | 역할 |
|---:|---|---:|---|
| 00 | anticipation | 140ms | 오른쪽에서 압화 여러 장을 하나의 살촉으로 조인다. |
| 01 | release | 100ms | 뒤쪽 꽃잎이 벌어지며 왼쪽으로 발사된다. |
| 02 | travel | 75ms | 긴 크림색 앞날로 이동 방향을 고정한다. |
| 03 | travel | 75ms | 접촉 직전 살촉을 작게 압축하고 끝점만 밝힌다. |
| 04 | contact | 70ms | 보이지 않는 접촉면에 작은 여섯 갈래 압화 별이 생긴다. |
| 05 | reaction | 100ms | 씨앗 중심을 남긴 채 제한된 꽃잎 파편이 왼쪽으로 열린다. |
| 06 | recovery | 160ms | 남은 꽃잎과 씨앗 중심이 작은 갈고리 형태로 풀린다. |

합계 720ms로 서버 `draw` 일반 모션의 6구간 시간과 정확히 같다. `travel` 150ms만
두 장으로 나눴으며, 피해 숫자·SFX·햅틱은 04번 접촉 프레임 이후에만 시작한다.

## Imagegen 생성 기록

- 모드: 내장 Imagegen, 신규 이미지 7회. CLI와 네이티브 투명 배경 모델은 사용하지
  않았다.
- 참조: 첫 포즈는 `paper-flurry`의 따뜻한 동화책 재질과 선 밀도만 참고했고, 이후
  여섯 포즈는 00번 포즈를 정체성 기준으로 참조했다. 장부 종이 실루엣은 복제하지 않았다.
- 공통 프롬프트: 모바일 RPG 전투 VFX 원본, 크림·황토·바랜 산호·따뜻한 갈색의 실제
  말린 압화, 꽃잎 맥과 마른 가장자리, 작은 씨앗 중심, 왼쪽을 향하는 선명한 삼각형
  실루엣, 절제된 손그림 동화책 마감, 캐릭터·대상·배경·UI·문자·그림자 제외.
- 포즈 프롬프트: `조임 → 방출 → 가는 비행 → 접촉 전 압축 → 작은 접촉 별 → 제한된
  압화 파편 → 갈고리형 회수`만 바꾸고 재질·팔레트·씨앗 중심은 유지했다.
- 크로마 프롬프트: 완전히 균일한 `#00FFFF`, 바닥·그라데이션·반사·후광 없음,
  피사체 내부 시안 사용 금지, 넉넉한 여백과 선명한 안티앨리어싱 가장자리.
- 원본: `sources/petal-dart/pose-*-chroma.png`
- 알파 마스터: `alpha/petal-dart/pose-*.png`

## 알파·런타임·블렌딩

Imagegen skill의 `remove_chroma_key.py`를 모든 프레임에 동일하게 적용했다. border 자동
키, soft matte, `transparent-threshold 12`, `opaque-threshold 220`, despill 조건이며
추가 edge contract나 수동 하드 키는 필요하지 않았다. 알파 추출 뒤 투명 모서리와
밝은·어두운 배경의 외곽선을 각각 확인했다.

- 런타임: `app/assets/adventure/effects/petal-dart-v1/frame-*.webp`
- 캔버스: 576×288, 7장, 프레임별 4px 이상 안전 여백
- 이동: `tangle_center → lowest_actor`, 오른쪽에서 왼쪽
- 블렌딩: 원화 RGB는 그대로 두고 `ember` 색은 16% `srcIn` 블러 레이어에만 섞는다.
- QA: `qa/petal-dart-v1-light-dark.webp`, `qa/petal-dart-v1-preview.webp`
- 무결성: source·alpha·runtime 개별 SHA-256과 source/runtime aggregate SHA-256을
  `manifest.json`과 앱 manifest에 보존한다.

`production_ready`는 실제 기기 1×/2× 재생, 밝은·어두운 전투 배경, 저감 모션,
저사양 GPU 디코드·블렌딩 프로파일을 통과한 뒤에만 `true`로 올린다.
