# 품종별 걷기 도트 v1 — 던전을 걷는 사람이 내 캐릭터가 된다

생성일: 2026-09-01
생성 도구: ChatGPT ImageGen(`gpt-image` 스킬 배치) → `prepare_walker_strip.py` → `import_expedition_walker.py`
상태: **앱 연결 완료(코드 수정 없음) / 카탈로그 18종 중 17종 / 새싹몬은 공용 시트 그대로**

## 왜 만들었나

던전을 걷는 화면은 탐험에서 **가장 오래 보는 화면**인데, 어떤 캐릭터로
들어가도 같은 새싹 여행자가 걸었다. 자리는 이미 열려 있었다 —
`expeditionWalkerAssetCandidates`가 `expedition-walker-<품종>-v1.png`를 먼저
찾고 없으면 공용 시트로 떨어진다. 코드가 아니라 그림이 없었을 뿐이다.

게임 배율에서 캐릭터는 30~40픽셀이다. 옷의 무늬가 아니라 **실루엣과 색 두세
개**로 갈린다. 그래서 만개 원화를 그대로 줄이는 대신, 그 캐릭터에서 그 크기에
남는 것만 골라 다시 그리게 했다.

| `aloof-pot` | 서리동백 설화 | 은발 + 검은 안대 + 크림 코트 | `260F81379F00E3842D694A40E85AC9BAAD2C702869550C94B932B56D82FA7342` | 10KB |
| `baby-pot` | 아기 화분 뽀또 | 해바라기 꽃잎 후드 + 잎사귀 원피스 | `DB960DD81A06922E0798080CBF6B8D7A03E12A197D3FF1D207284DA3223B60E2` | 12KB |
| `cactus` | 가시니 | 붉은 꽃 얹은 둥근 초록 선인장 | `7EAFD409F07AE283E77B1DA6599AE6B3941446AFAEEFD5BF67F0C5F12AF69ACA` | 10KB |
| `gal-pot` | 스타일 메이커 리아 | 금발 + 흰 가디건 + 짧은 회색 치마 | `C9E50B5F33D523172CD4957D19873E2CFC4A90FD717E838D473ADC45A3C5A496` | 9KB |
| `gumiho-pot` | 구미호 여우비 | 검은 여우귀 + 산호빛 한복 + 흰 꼬리 | `88FA3ECF1A5E5B496849895A51BB8D0C6EBB0A1A2310F6C4ED0255F52D0544EF` | 12KB |
| `handsome-pot` | 냉미남 로제온 | 검은 머리 + 금장 크림 코트 + 긴 부츠 | `BC4D57371FFA4489E23A5530F991FF7E7027B282D2A10B9AD4365D6905B5B003` | 11KB |
| `maestro-pot` | 공명 지휘자 세렌 | 보라 단발 + 민소매 드레스 + 지휘봉 | `78C1885BC649F094CF3433D99A27B125C6957DD61E3E5CF45F27566B85FA493B` | 10KB |
| `magical-pot` | 마법사 별솔 | 챙 넓은 회색 모자 + 해바라기 | `8E2CFADC2B34D95C0813F0BA4169E1D50754EBA90A543CC6D5E49D8E329E7BDC` | 13KB |
| `marten-pot` | 잎귀 담비 모루 | 네발로 걷는 복슬 담비 + 잎빛 꼬리 | `D62B3B6E3D1547C9563F976850F613CE22841593F9127460E8B6479CE4021081` | 12KB |
| `ninja-pot` | 닌자 그림싹 | 짙은 초록 후드 + 잎사귀 망토 | `C42D74A05CE060FE4DBF680EF8B6DF371596F4869125EEFC3305A1511ECE7D6D` | 11KB |
| `nurse-pot` | 백의 수호사 백화 | 금발 + 흰 가운 + 붉은 주사기 | `1F81B1D5E1AB3814827D8A180080780B8CB5F595A4B0BEABE6B5AA42898C3665` | 10KB |
| `pretty-pot` | 센터 아이돌 블루미 | 분홍 머리 + 꽃잎 드레스 + 긴 리본 | `1DC66F4B8AFDE076ABC8250B39CB45199280FB887507F7207A348C9E0CB653E1` | 11KB |
| `restorer-pot` | 황혼 복원사 에단 | 회색 셔츠 + 갈색 바지, 넷 중 가장 수수함 | `283A57D395EEF5267292211F42B02FD291010AF983747E064F7B7C4B040E8FB5` | 9KB |
| `student-pot` | 학생회장 하루 | 주황 머리 + 올리브 코트 + 초록 책 | `E55B9219BCF47AC42310412227719769578923AFF134AF81A610492600566F59` | 10KB |
| `sunflower` | 해바라기 | 큰 해바라기 갈기 + 잎사귀 팔 | `EB1CEBD293F5E7B49227CB280374604DDFF2B84FA8823EC9982488C4FA163090` | 12KB |
| `tsundere-pot` | 선인장 츤데레 가시로 | 붉은 뻗친 머리 + 주황 겹옷 | `593328D569ABB64F6C69B4CAD87D3B3D76CC7550EF89A79BEA813F10E9B69106` | 11KB |
| `zombie-pot` | 좀비 화분 시들잎 | 연보라 물결 머리 + 데이지 지팡이 | `7E23FA53996BA55627DCF641F2E420BF804A5A4DED16D06EA024B7754161326A` | 12KB |

**새싹몬(`basic_sprout`)만 자기 시트가 없다.** 공용 시트가 곧 새싹몬이라 같은
그림을 두 번 넣는 일이 된다. 이건 빠뜨린 것이 아니라 정한 것이고,
`expedition_walker_asset_test.dart`가 그 자리에 파일이 **없는지**까지 확인한다.

## 굽는 순서

받은 그림을 바로 넣지 않는다. 두 단계를 거친다.

```bash
# 1. 생성 결과 넉 장(방향별) → 288×120 띠 넉 장
python design-system/scripts/prepare_walker_strip.py     --down out/ninja-down.png --left out/ninja-left.png     --right out/ninja-right.png --up out/ninja-up.png     --out-dir tmp/walker/strips-ninja

# 2. 검사 + 굽기 → app/assets/adventure/overworld/
python design-system/scripts/import_expedition_walker.py     --strips tmp/walker/strips-ninja/walk-{down,left,right,up}.png     --species ninja-pot
```

1단계가 이번에 새로 생겼다. 생성 결과에 두 가지 문제가 **매번** 있었다.

* **투명 배경을 픽셀로 그려 준다.** 알파를 비우는 대신 회색 체크무늬를 칠해
  놓는다(알파는 전부 255). 그대로 구우면 캐릭터 뒤에 체크무늬가 박힌다.
  가장자리에서 번지며 그 색만 지운다 — 색으로 한 번에 지우면 얼굴의 밝은
  색까지 날아간다. 2026-08-18 기록이 "가장자리를 훼손한다"며 포기한 바로 그
  문제이고, 번지는 방식이 답이었다.
* **한 번에 줄이면 도트가 아니라 노이즈가 된다.** 1536픽셀 그림을 96픽셀로
  곧장 줄이면 자수·머리카락 같은 잔무늬가 픽셀마다 튀는 값으로 남는다.
  마법사 시트가 자글거림 **0.238**로 걸렸다(한계 0.16). 알파를 곱한 뒤 세
  번에 나눠 줄이니 **0.146**이 됐다.

`냉미남 로제온`만 세 단계로도 0.168이 나와 `--smooth 4`로 한 단계 더 줬다
(0.152). 검사를 느슨하게 하는 대신 **통과하는 가장 적은 단계**를 쓴다.

방향마다 키도 맞춘다. 판 크기가 방향마다 달라서(1536×1024, 1920×819 …) 그냥
줄이면 아래를 볼 때와 옆을 볼 때 캐릭터 키가 달라진다.

`잎귀 담비 모루`는 네발 짐승이라 생성이 **오른쪽을 끝내 안 그렸다** — 넉 장을
받아 보니 옆모습 둘 다 왼쪽을 봤다. 좌우가 거의 대칭인 캐릭터라 `--mirror-right`로
왼쪽 띠를 뒤집어 만들었다. **칸마다** 뒤집는다. 띠를 통째로 뒤집으면 프레임
순서까지 거꾸로 돼서 왼발과 오른발이 바뀐다.

## 산출물 규격

288×480 PNG, 3프레임 × 4방향(아래·왼쪽·오른쪽·위), 24색, 알파 1비트.
자글거림 실측은 0.044(담비) ~ 0.152(로제온), 한계 0.16. 튀는 점은 전부
0.0004 이하, 한계 0.002.

공용 시트(7KB)는 그대로 둔다. 새 품종이 들어오면 그림이 오기 전까지 그 길로 걷는다.

## 프롬프트

같은 뼈대를 쓰고 **옷차림 한 문단과 시점 한 문장**만 갈아 끼운다. 참고 그림은
둘을 함께 넘긴다 — 기존 걷기 띠(화풍·3칸 배치)와 그 품종의 만개 원화(색·옷).

공통 뼈대:

> Pixel art walk-cycle strip for a top-down 2D RPG, on a plain flat empty background. Three frames of the same character side by side in three equal columns, every frame at the same scale with the feet resting on one shared baseline near the bottom of the image, and clear empty margin above the head and below the feet. {옷차림} {시점} First column: left leg forward mid-step. Second column: standing still with both feet together. Third column: right leg forward mid-step. Chunky readable pixel art with hard aliased edges and flat blocks of color. No dithering, no gradients, no anti-aliasing, no glow, no outline halo, no cast shadow, no ground, no floor, no scenery, no text, no numbers, no frame borders, no grid lines. Limited palette of about twenty colors.

시점 넷:

> **down** — The character faces the viewer straight on, seen from a slightly elevated angle so the top of the head and the pot rim are both visible.
> **left** — The character is seen in full side profile walking to the viewer's left, one shoulder toward the camera.
> **right** — The character is seen in full side profile walking to the viewer's right, one shoulder toward the camera.
> **up** — The character is seen from behind walking away from the viewer, so only the back of the head, the back of the robe and the back of the pot are visible, with no face showing.

옷차림은 열일곱 종마다 한 문단이다. 공통 뼈대 둘을 모든 문단이 공유한다 —
`whose lower body is a round terracotta flower pot`(담비만 제외)과
`two small green sprout leaves rise from the top of the head`. 이 둘이 열일곱을
한 무리로 묶는다. 예를 들어 닌자는 이렇게 썼다.

> The character is a small chibi plant-spirit ninja whose lower body is a round terracotta flower pot: dark forest-green hood pulled up, a leaf-shaped cloth mask covering the lower face, narrow pale eyes, a long ragged green leaf cape, black wrapped legs and small dark boots, and two little green sprout leaves rising from the top of the hood.

담비만 다르다. 화분도 사람 몸도 없다.

> The character is a small chibi plant-spirit marten: a fluffy four-legged golden-brown weasel-like animal with a long bushy tail, big round dark eyes, and leaf-green tips on its ears and tail, wearing a small acorn pendant on a green cord. It walks on all four legs. It has no flower pot and no human body.

## 앱 연결

**코드는 한 줄도 고치지 않았다.** 파일을 놓으면 그 품종부터 새 시트로 걷는다.
다만 폴백이 조용해서 파일이 빠지거나 규격이 어긋나도 화면만으로는 모르므로,
`expedition_walker_asset_test.dart`가 매번 확인한다 — 열일곱이 후보 목록 첫
자리에서 열리는지, 288×480인지, 알파가 1비트이고 24색 이하인지, 열두 칸이 모두
차 있고 위아래로 잘리지 않았는지, **서로 그리고 공용 시트와 충분히 다른지**,
그리고 새싹몬 자리에는 파일이 **없는지**.
