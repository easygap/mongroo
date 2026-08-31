# 합동 수호전 꿈 배경 v1 — 수호짐승 넷의 꿈

생성일: 2026-08-31
생성 도구: ChatGPT ImageGen(`gpt-image` 스킬 배치)
상태: **앱 연결 완료 / production candidate / 실기 QA 미완료**
관련 설계서: `docs/guardian_raid_design.md` 4.5 · 6장

## 왜 이 넷인가

합동 수호전은 짐승 넷이 **수치 구조를 공유한다**. 장벽도 라운드도 결정적 순간의
시점도 같고, 다른 것은 겹별 상성과 연출·서사뿐이다(설계서 4.5). 그래서 배경까지
공용 수호전 무대를 쓰면 `깊은 꿈`이 그냥 한 판 더가 된다 — 넷을 구분해 주는 것이
상성표 두 줄밖에 남지 않는다.

배경은 짐승이 **무엇을 끌어안고 있는지**를 말 없이 보여 주는 자리다.

| 짐승 | 끌어안은 것 | 꿈에서 보이는 것 |
| --- | --- | --- |
| 돌비늘 장부지기 | 분류 못 한 기억 장부 | 페이지가 눈처럼 내린다 |
| 물거울 메아리지기 | 주인 못 찾은 메아리 | 소리가 물결로 보인다 |
| 별가루 씨앗지기 | 때가 안 된 씨앗함 | 별빛이 모래처럼 쌓인다 |
| 옹이등 기록지기 | 완성 못 한 기록 한 장 | 나이테가 물결친다 |

## 구도 계약

넷 다 기존 수호전 무대(`expedition-monster-den-battle-v1`)의 구도를 따른다.
이 배경 위에 전투 스프라이트가 그대로 얹히기 때문이다.

- 살짝 내려다보는 3/4 시점.
- **아래 가운데는 완전히 빈 둥근 바닥.** 여기에 대원 셋과 짐승이 선다. 여기에
  무언가를 그리면 스프라이트와 겹친다.
- 바깥은 구조물·식생으로 감싸고 가장자리는 비네트로 어둡게.
- 글자·사람·생물 없음. 짐승 자신도 배경에 그리지 않는다 — 스프라이트로 따로 선다.

## 산출물·해시

master는 1672×941 PNG, runtime은 1600×900 WebP와 960×540 모바일 파생본이다.
(기존 장면 원화와 같은 규격이다.)

| beast code | master SHA-256 | runtime SHA-256 | mobile SHA-256 |
| --- | --- | --- | --- |
| `ledger_keeper` | `4E71DA95D1DFFA467AEA4A45695B4538B5FCED016025F34A399CAE83C3F672E9` | `04BCD615B63FF2BDDC17379213A45E9FA6D4895EF309595A152E38524EC30817` | `3E4A1EF35E5E7755F7602B088CEFE680002E234380F67A1614850ED139E24B5F` |
| `echo_keeper` | `668EEC43F755F229AF80E0914BF8ECF5CFD90405875A183FDF9DB310D59D7011` | `2D9B35B9802101DF2C09EA2DA296B468DCCCDF76D9686F532937FBC63D2ED427` | `E36D0A32EC07FBF76A02BA4D454BDEDC203EAD2E3EBB7AFB9A5DFC3F2756086A` |
| `seed_keeper` | `331444CE186D21A6C0539FD7D1CC4E1663FDCCF66D21582691A4C613497643C4` | `B12C67B2DA51395BF552D58BF8EA09177DB6470387179332DAE8B768098F17BF` | `8AA8F068973FE3326530DB446A13A093E1E6406565DC65CBB9E8ABE23BB02F60` |
| `record_keeper` | `BBC1CB8BDBE4C75B716C0CE2577276377C820590711B732DD530CE6B377C2416` | `D0D740667EC47470BAD2E2295DA01922E94BE2F345FDC5692C9E7B3A9B247D01` | `FFC4AA371494853E319BB6FD985E62AA3F54FEC53EBC67E9D4AF5548B88EE49B` |

용량은 runtime 159~234KB, 모바일 64~99KB로 기존 장면 원화(186KB/91KB)와 같은
밴드에 있다.

## 강조색

배경에서 실제로 빛나는 색을 그대로 골랐다. 겹 배지와 예고 강조가 이 색을 쓴다.

| beast code | accent | 어디서 온 색인가 |
| --- | --- | --- |
| `ledger_keeper` | `#E8C77A` | 등불에 비친 양피지 |
| `echo_keeper` | `#72D6DD` | 퍼져 나가는 소리 물결 |
| `seed_keeper` | `#CBB6F2` | 쌓인 별가루의 보랏빛 |
| `record_keeper` | `#E0A76A` | 옹이등의 호박색 |

## 프롬프트

넷 다 같은 구도 제약을 공유하고 세계만 다르다. 아래는 실제로 보낸 문장이다.

**ledger_keeper**

> Painted storybook illustration of a cozy dream library interior, seen from a slightly elevated three-quarter view looking down. The lower center is a wide, completely empty rounded floor of pale worn stone tiles, clear and unobstructed, forming a stage. Around and behind it rise tall leaning bookshelves of mossy old ledgers and account books, their spines bound in leather straps. Loose paper pages drift down through the air like falling snow, catching soft light. A few warm brass lanterns glow on stone pedestals at the edges. Muted sage green, warm parchment cream, and soft brown palette with gentle amber lantern light. Dreamlike and calm rather than spooky. Soft painterly shading, storybook game background art, dark vignette at the outer edges framing the scene. No characters, no people, no creatures, no text, no letters, no words, no numbers, no UI. 16:9 widescreen.

**echo_keeper**

> Painted storybook illustration of a cozy dream well garden at night, seen from a slightly elevated three-quarter view looking down. The lower center is a wide, completely empty rounded floor of smooth wet flagstones, clear and unobstructed, forming a stage. Behind it stands an old circular stone well ringed with ferns, and the air itself is filled with visible concentric ripples of sound spreading outward like water rings, glowing faint cyan. Still reflecting pools edge the scene, mirroring the ripples. Deep teal, moonlit blue, and cool grey stone palette with soft cyan glow and a few warm lantern points. Dreamlike, hushed and gentle. Soft painterly shading, storybook game background art, dark vignette at the outer edges framing the scene. No characters, no people, no creatures, no text, no letters, no words, no numbers, no UI. 16:9 widescreen.

**seed_keeper**

> Painted storybook illustration of a cozy dream seed vault interior, seen from a slightly elevated three-quarter view looking down. The lower center is a wide, completely empty rounded floor of pale sandy stone, clear and unobstructed, forming a stage. Behind it rise curved wooden cabinets of small labelled seed drawers, and fine glittering starlight falls and piles up in soft drifts like luminous sand along their bases. Tiny motes of star dust hang suspended in the air. Deep indigo night, soft violet shadow, warm pale gold starlight palette. Dreamlike, quiet and full of held breath. Soft painterly shading, storybook game background art, dark vignette at the outer edges framing the scene. No characters, no people, no creatures, no text, no letters, no words, no numbers, no UI. 16:9 widescreen.

**record_keeper**

> Painted storybook illustration of a cozy dream observatory built inside a vast living tree, seen from a slightly elevated three-quarter view looking down. The lower center is a wide, completely empty rounded floor of polished wood, clear and unobstructed, forming a stage. The surrounding walls and floor are made of enormous tree rings that ripple outward in slow concentric waves like water, warm and organic. A round window opens to a soft night sky above, and knot-shaped lanterns glow amber in the alcoves. Warm honey brown, deep amber, and soft cream palette with gentle golden light. Dreamlike, warm and drowsy. Soft painterly shading, storybook game background art, dark vignette at the outer edges framing the scene. No characters, no people, no creatures, no text, no letters, no words, no numbers, no UI. 16:9 widescreen.

## 앱 연결

`joint_guard_battle_view.dart`의 `dreamSceneFor(beastCode)`가 짐승 코드로 배경과
강조색을 고른다. **지역 보정색은 넘기지 않는다** — 이 배경은 그 꿈 전용으로 그린
원화라, 지역 색을 한 번 더 얹으면 두 번 물든다(`expeditionRegionGrade`가 전용
원화에는 보정을 안 거는 것과 같은 이유다).

원화가 없는 짐승은 공용 수호전 무대로 조용히 물러난다. 조용한 폴백은 눈으로
잡기 어려우므로 `joint_guard_dream_asset_test.dart`가 네 짐승 모두 자기 파일을
갖는지, 서로 다른지, 모바일 파생본과 강조색이 함께 있는지를 매번 확인한다.
