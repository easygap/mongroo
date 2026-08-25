# 프리미엄 지원가 서사 기반 재설계 v6

`docs/premium_support_character_bible_v6.md`의 서사를 먼저 확정한 뒤 백화와 세렌을
서로 다른 도형 언어로 다시 제작했습니다. 기존 로스터는 선화·셀 채색의 밀도만
참고했으며 얼굴, 머리, 체형, 의상과 포즈는 복제하지 않았습니다.

- 백화: 원과 곡선, 펄 블론드 장발, 풍만하고 안정적인 체형, 짧은 백색 현장 코트,
  대형 앰플 인젝터
- 세렌: 삼각형과 직선, 잉크 바이올렛 단발, 길고 각진 체형, 무소매 테일러드 롬퍼,
  흑단 지휘봉
- 공통: 또렷한 애니메이션 선화, 2~3단 셀 채색, 장식·파티클·후광 없는 전신 원화

`sources/`는 Imagegen 크로마 원본, `alpha/`는 로컬 크로마 제거 마스터입니다.
앱용 512×768 WebP는 `design-system/scripts/build_premium_character_v6.py`로
재생성합니다.

![기존 로스터와 v6 화풍·정체성 비교](character-style-identity-v6.webp)

## 성장 시트 생성 규격

만개만 있던 두 사람의 씨앗~개화 네 단계를 채우기 위한 규격이다. 각 단계가
어떤 모습인지는 `docs/premium_support_character_bible_v6.md`의 `성장 계보`
절이 단일 원본이고, 여기서는 파일 규격과 프롬프트만 다룬다.

- **낱장 넷을 권장한다.** `alpha/{slug}-seed.png`·`-sprout.png`·
  `-branching.png`·`-bloom.png`. 네 나이를 한 번에 요구하면 칸마다 얼굴이
  흔들리고, 낱장이면 마음에 안 드는 칸 하나만 다시 굽는다. 네 칸을 한 줄로
  담은 `{slug}-growth.png` 시트도 그대로 받는다. 만개는 이미 있는
  `{slug}-v6.png`를 쓴다.
- **낱장은 키를 맞추지 않는다.** 각 파일에서 인물이 캔버스를 채우게 그리면
  된다. 빌드가 만개 키를 1로 두고 단계별 비율(0.23·0.66·0.87·0.975)로 앉힌다.
  사람형 계보 둘의 실측 평균이다. 시트로 주면 칸 사이의 상대 크기를 그대로
  쓰므로 그때는 한 시트 안에서 키 차이를 실제 비율로 그려야 한다.
- 크로마 제거는 `design-system/scripts/extract_green_sprite.py`가 한다.
  초록 우세도로 자르고 가장자리 띠에만 despill을 걸어, 떡잎처럼 진짜 초록인
  부분을 죽이지 않는다.
- 크로마 원본은 균일한 `#00FF00`, `sources/{slug}-growth-chroma.png`.
  크로마를 제거한 투명 마스터는 `alpha/{slug}-growth.png`.
- 시트로 줄 때 칸 사이는 캐릭터 폭의 10% 이상 비운다. 자동 분할이 빈 세로
  구간에서 칸을 가른다 - 붙여 놓으면 두 칸을 하나로 읽는다.
- 발끝을 한 줄에 맞춘다. 바닥선, 그림자, 텍스트, 패널 테두리, 번호는 넣지
  않는다.
- 감정 여섯 결은 만들지 않는다. 빌드가 중립본에서 파생한다.

빌드는 이렇게 돈다. numpy가 필요해 `design-system/requirements.txt` 환경에서
실행한다.

```
python design-system/scripts/build_premium_character_v6_growth.py
```

캐릭터당 런타임 28개(중립 4단계 + 감정 6결x4단계)와 6결x5단계 검수 시트를
`qa/`에 남기고, 원본과 산출물 해시를 `qa/premium-character-v6-growth.json`에
적는다. 만개 중립본은 다시 만들지 않는다 - 배율 기준이 달라(468 대 448)
지금 빌드에 들어간 파일이 소리 없이 바뀐다.

시트를 넣고 빌드한 뒤 `app/test/plant_sprite_coverage_test.dart`의 `knownGaps`
에서 `maestro-pot`·`nurse-pot` 여덟 줄을 지운다. 안 지우면 테스트가 실패해서
알려 준다.

### ImageGen 프롬프트

**한 칸씩 따로 만든다.** 네 나이를 한 번에 요구하면 칸마다 얼굴이 흔들린다.
`ADVENTURE_ASSET_PROMPTS.md`가 이미 같은 말을 한다 - 여러 프레임을 한 번에
요구하지 않는다. 걷기 시트도 방향마다 한 장씩 받는 쪽이 실측으로 나았다.
빌드는 `alpha/{slug}-{phase}.png` 낱장 넷을 먼저 찾고, 없으면 한 장짜리
시트로 넘어간다. 낱장이면 나쁜 칸 하나만 다시 구우면 된다.

입력 1은 그 캐릭터의 만개 마스터(`alpha/{slug}-v6.png`)를 **매 칸마다** 넣는다.
얼굴이 흔들리지 않게 잡아 주는 유일한 닻이다.

두 번의 실패에서 배운 것을 프롬프트에 박았다.

- **점묘.** `docs/overworld_imagegen_qa_2026-08-18.md`의 금지 블록을 그대로
  넣는다. 이 저장소가 오버월드에서 이미 겪고 정리해 둔 목록이다.
- **작은 어른.** `prop progression`과 시그니처 자세를 어린 단계에 내리라고
  지시했더니 아이가 직업복을 입고 나왔다. 이제 금지로 바꿨다.
- **칙칙함.** 1~4단계를 전부 덮으라고 했더니 백화는 온통 흰색, 세렌은 온통
  검정이 됐다. 승인된 리아·에단은 모든 단계에서 맨팔·맨다리가 나오고 색도
  두세 가지를 섞는다. 그 기준으로 고쳤다.

```text
Use case: character-growth-panel
Asset type: one isolated full-body mobile game character illustration for 2D cleanup
Input image: the exact approved adult identity for this character. The figure you draw is the same person at a younger age.
Primary request: {stage_line}
Identity lock: preserve the shape language, hair color, eye color, skin tone, eye shape, warm ink outline weight, and soft upper-left key light from the input. The adult in the input must read as the same person grown up.
Age readability: {age_note}
Palette: use two or three clothing colors, not one. Do not dress the figure in a single tone. The character's signature color is one of the colors, not the color of everything.
Skin: everyday seasonal clothing with bare arms and bare legs where the outfit naturally shows them. Do not cover the whole body - a fully covered figure reads as a uniform and kills the picture.
{maturity_line}
Style/medium: Mongroo 2D mobile game character illustration, clean flat cel shading in two or three steps, crisp even ink outline, simple readable face and hands, hair as large masses with few interior lines, broad contiguous color shapes, limited palette.
Screen: exactly one full-body figure, standing on one baseline, solid #00FF00 background, no floor, no cast shadow, no text, no numbers, no panel border, no particles, no halo.
Avoid: stippling, pointillism, dithering, grain, film noise, speckles, random brush dots, micro-detail clutter, painterly impasto, watercolor bloom, photorealistic scan texture, over-sharpening, generative texture mush, AI artifact clusters, excessive detail, identity drift from the input, extra fingers or limbs, realistic anatomy, glossy 3D toy rendering, neon rim light, cropped hair, cropped feet.
```

`{stage_line}`은 바이블 `성장 계보` 표의 해당 줄, `{age_note}`와
`{maturity_line}`은 아래를 쓴다.

| 단계 | age_note | maturity_line |
|---|---|---|
| 씨앗 | (칸 없음 - 아래 씨앗 전용 판을 쓴다) | - |
| 새싹 | `a child of about 7 - large head, round eyes, short limbs.` | `This is a child. No body-conscious tailoring, no waist or chest emphasis, no alluring expression or pose. Draw the clothes a seven-year-old actually wears.` |
| 가지 | `a teenager of about 14 - the head-to-body ratio has lengthened but the build is still slight.` | `This is a teenager. No body-conscious tailoring, no waist or chest emphasis, no alluring expression or pose.` |
| 개화 | `a young adult of about 21 - full adult proportions, slightly lighter than the mature master.` | `This is a young adult. Youthful and lively is right - cropped or short hems and visible midriff are fine. Keep mature and sensual staging for the separate adult master.` |

씨앗 칸은 사람이 아니라서 따로 쓴다.

```text
Use case: growth-seed-panel
Asset type: one isolated seed illustration for a mobile game growth lineage
Primary request: {seed_line}
Reference for scale and treatment: a game seed sprite that reads instantly as a seed - a rounded shell with two small cotyledon leaves.
Screen: exactly one seed, solid #00FF00 background, no jar, no glass, no cup, no pot, no container of any kind, no floor, no cast shadow, no text, no particles, no halo.
Style/medium: Mongroo 2D mobile game asset, clean flat cel shading in two or three steps, crisp even ink outline, broad contiguous color shapes, limited palette.
Avoid: stippling, pointillism, dithering, grain, film noise, speckles, random brush dots, micro-detail clutter, painterly impasto, watercolor bloom, photorealistic scan texture, over-sharpening, generative texture mush, AI artifact clusters, excessive detail, any container, a gem or crystal or bottle reading, ornate metal, excessive detail.
```

낱장은 **키를 맞추지 않아도 된다.** 빌드가 네 칸에 같은 배율을 먹이므로
그리는 사람이 아니라 파일 안의 실제 비율이 성장 곡선을 만든다. 씨앗은 새싹의
1/4 높이쯤으로, 각 낱장은 인물이 캔버스를 꽉 채우게 그린다.

넣고 빌드하면 점묘 관문이 먼저 돈다. 승인된 원화 실측이 고주파 0.036~0.050,
튀는 점 0.0001~0.0003이라 한계를 0.075/0.0010으로 잡았다. 넘으면 어떤 값이
얼마나 넘었는지 적고 멈춘다.

안전 필터에 막히면 같은 프롬프트를 반복하거나 표현을 바꿔 우회하지 않는다.
