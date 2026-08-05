# 몽그루 직접 탐험 스킬트리 90노드 카탈로그

최종 갱신: 2026-08-04
상태: 구현·콘텐츠 원본 확정안
대상 버전: `expedition-skill-trees-v1`

이 문서는 `interactive_adventure_design.md` 7.3의 품종별 스킬트리를 실제 콘텐츠
파일로 옮길 수 있도록 10품종의 배분 노드 90개를 모두 정의한다. 이 문서와 YAML이
다르면 YAML 생성 전에 문서를 고치고 두 산출물의 hash를 CI에서 비교한다.

## 1. 사용 규칙

- 식물 하나는 stage 3/4/5에서 누적 1/2/3포인트를 얻는다.
- 뿌리 고유 스킬은 자동 해금이며 포인트를 쓰지 않는다.
- 세 갈래마다 1~3단이 있고, 같은 갈래의 앞 단계를 선행 조건으로 요구한다.
- 배분 노드는 새 고정 버튼을 만들지 않는다. 유효한 상황에서 지도·이동·사건·스킬·
  쉼터에 문맥 칩으로 나타난다.
- 모든 노드는 한 leg에 1회, 한 확정 행동에는 노드 하나만 사용한다.
- `skill` 노드는 고유 스킬의 기본 효과에 보너스를 더하지 않고 표에 적힌 대체 효과로
  교체한다. 고유 스킬 1회와 노드 1회를 함께 소비한다.
- `move|choice` 노드는 해당 행동과 한 트랜잭션에서 확정한다.
- `map` 노드는 정보를 공개하거나 귀환 표식을 놓는 독립 행동이다. 유효 대상이 없으면
  칩을 노출하지 않고 사용 횟수도 소비하지 않는다.
- `camp` 노드는 아직 회복을 쓰지 않은 쉼터에서만 사용한다.
- 노드 효과는 XP, 씨앗, loot 수량·가치, 유대, 친숙도, 영구 stat, stage, 스킬 충전량을
  늘리지 않는다.

## 2. API와 런타임 상태

| activation | API | 원자적 처리 |
|---|---|---|
| `map` | `POST /expeditions/{id}/tree-actions` | 정보 공개·anchor 저장과 node 소비 |
| `move` | `POST /expeditions/{id}/move` | 이동 비용/지도 상태 변경과 node 소비 |
| `choice` | `POST /expeditions/{id}/choices` | 판정·결과·지원 예약과 node 소비 |
| `skill` | `POST /expeditions/{id}/skills` | 고유 스킬 대체 효과와 두 사용 횟수 소비 |
| `camp` | `POST /expeditions/{id}/camp` | 회복 또는 합법적 재배분과 node 소비 |

`tree-actions` 요청은 `member_id`, `node_code`, `target_node_code` 또는
`target_edge_code`, `expected_revision`, `client_action_id`를 받는다. 다른 endpoint는
기존 요청에 선택 `skill_node_code`와 `node_params`를 받는다. `node_params`는 임의 JSON이
아니라 아래 module별 닫힌 schema이며, 불필요한 키가 하나라도 있으면 422다.

| module | `node_params` | 서버 검증 |
|---|---|---|
| `node_tag_peek` | `{target_node_code}` | 현재 위치와 거리 1, 미방문·공개 방향 |
| `node_cost_peek` | `{target_node_code}` | 공개된 방향을 따라 거리 2 이내 |
| `hidden_edge_hint` | `{origin_node_code, direction_code}` | origin은 현재/방문, 그 방향에 미공개 간선 존재 |
| `safe_choice_hint` | `{target_choice_code}` | 현재 사건의 `safe=true` 선택 |
| `trail_discount` | `{}` | move의 `node_code`가 미방문이고 비용 1 이상 |
| `resolve_guard` | `{}` | choices의 결과표에 `detour`가 존재 |
| `actor_handoff` | `{target_member_id}` | 다른 실제 party member, 길잡이 제외 |
| `signature_retarget` | 노드 정의의 `parameter_schema` | 아래 10개 노드별 허용 키·enum·소유권을 정확히 검사 |
| `choice_stat_flex` | `{replacement_stat_code}` | 행동자의 네 stat 중 원래 요구 stat과 다른 하나 |
| `event_tag_flex` | `{}` | `choice_code`가 사건의 허용 `flex_choices`에 존재 |
| `return_anchor` | `{}` | 현재 node가 이미 방문한 `camp|entrance` |
| `map_state_guard` | `{target_edge_code}` | 현재 장치 전환으로 닫힐 공개·열린 간선 |
| `story_consequence_hint` | `{target_choice_code}` | 현재 사건에 존재하고 미해결인 선택 |
| `camp_reconfigure` | `{replace_node_code, new_node_code}` | 같은 tier, 선행·포인트 충족, 영구 build는 불변 |

`signature_retarget.parameter_schema`도 콘텐츠에 닫힌 값으로 저장한다. 대상이 필요 없는
노드는 `{}`, 다른 멤버를 지정하면 `{target_member_id}`, 능력치 변경이면
`{replacement_stat_code}`, 노드/간선 대상이면 `{target_node_code}` 또는
`{target_edge_code}`만 허용한다. 각 행의 정확한 효과에 대상이 명시되지 않은 경우 서버가
임의 대상을 고르지 않고 요청을 422로 거절한다.

| signature node | 정확한 `parameter_schema` |
|---|---|
| `baby-pot.shelter.3` | `{}` |
| `handsome-pot.command.2` | `{target_choice_code, replacement_stat_code}` |
| `pretty-pot.rapport.3` | `{target_member_id, target_choice_code}` |
| `tsundere-pot.guard.3` | `{target_member_id}` |
| `zombie-pot.night_sense.3` | `{target_node_code}` |
| `gumiho-pot.foxfire.3` | `{target_node_code}`; 공개된 `deep` tag 방만 허용 |
| `ninja-pot.relay.2` | `{target_member_id, target_node_code}` |
| `magical-pot.transmute.3` | `{target_choice_code}` |
| `aloof-pot.shared_insight.2` | `{target_member_id, target_choice_code}` |
| `student-pot.group_study.2` | `{target_member_id}` |

run의 `runtime_effects_snapshot`은 다음처럼 크기가 제한된 상태만 저장한다.

```json
{
  "next_actor_support": null,
  "return_anchor": null,
  "revealed_hints": [],
  "guarded_edge": null
}
```

- `next_actor_support`는 한 건만 존재하며 다른 행동자가 다음 사건 choice를 확정하면
  +1을 적용하고 삭제한다. 해당 멤버가 파티에 없거나 run이 끝나면 소멸한다.
- `return_anchor`는 한 건만 존재하며 방문한 길로 연결된 현재 위치에서 1회 귀환한 뒤
  삭제한다. 잠긴 간선·미방문 방을 건너뛰지 않는다.
- 공개 hint는 node state를 `visited`로 바꾸지 않으며 경제·사건 내용을 미리 지급하지
  않는다.
- 동일 stack group의 미소모 pending effect가 있으면 새 칩을 노출하지 않는다.

## 3. 허용 effect module 14개

| module | activation | 정확한 효과 | stack group |
|---|---|---|---|
| `node_tag_peek` | map | 현재 위치에서 간선 거리 1인 미방문 노드 하나의 `node_type`과 공개 tag 1개를 reveal. 노드·사건 code는 숨김 | `map_reveal` |
| `node_cost_peek` | map | 공개된 방향을 따라 간선 거리 2 이내 노드 하나의 정확한 길빛 비용과 필수 사건 여부를 reveal | `map_reveal` |
| `hidden_edge_hint` | map | 현재 또는 방문 노드에 붙은 숨은 간선 하나의 방향만 reveal. 목적지·보상·event code는 숨김 | `map_reveal` |
| `safe_choice_hint` | map | 현재 사건의 안전 선택이 열 경로의 다음 `node_type`과 준비도 비용을 choice 전에 reveal | `event_hint` |
| `trail_discount` | move | 이번 미방문 노드 이동 길빛 비용 -1, 최소 0 | `move_cost` |
| `resolve_guard` | choice | 이번 choice 결과가 `detour`일 때 준비도 손실 1회 방지 | `resolve_protection` |
| `actor_handoff` | choice | 현재 사건 해결 뒤 지정한 다른 멤버의 다음 사건 choice 지원 +1. 1회 적용 후 삭제 | `next_actor_support` |
| `signature_retarget` | skill | 고유 스킬 기본 효과를 노드 표의 대체 대상·효과로 교체. 기본 효과와 합산하지 않음 | `signature_mode` |
| `choice_stat_flex` | choice | 선택한 일반 choice의 요구 stat을 행동자의 다른 stat 하나로 대체. DC와 결과표는 유지 | `stat_substitution` |
| `event_tag_flex` | choice | 콘텐츠에 정의된 `flex_choices` 중 노드 표의 tag용 choice 하나를 열어 정상 판정. 자동 clear 아님 | `event_tag` |
| `return_anchor` | map | 현재 방문한 camp/entrance를 1회 귀환 anchor로 저장. 방문 경로가 이어질 때만 사용 가능 | `return_anchor` |
| `map_state_guard` | move | 이번 장치 전환에서 지정한 열린 간선 하나를 다음 장치 전환까지 열린 채 유지 | `map_state` |
| `story_consequence_hint` | map | 현재 사건 choice 하나가 남길 story/discovery 결과 종류 1개를 미리 표시. 보상 수량 숨김 | `story_preview` |
| `camp_reconfigure` | camp | 배분 노드 하나를 같은 tier의 합법 노드로 교체. 사용 여부를 새 노드에 그대로 승계 | `camp_build_change` |

`amount`는 전부 1이다. `choice_stat_flex`의 stat 대체, `event_tag_flex`의 추가 choice,
`signature_retarget`의 대체 효과도 한 module로 계산한다. 서버가 표 밖의 두 번째 숫자
효과를 붙이면 validator가 실패한다.

## 4. 90노드 카탈로그

표의 1/2/3단은 각각 stage 3/4/5를 요구한다. 모든 노드의 비용은 1포인트,
`uses_per_leg=1`, `effect_budget=1`, `reward_affecting=false`다.

### 4.1 뽀또 — `baby-pot`

뿌리 스킬: `baby-pot.sprout-cheer` 새싹 응원 — 다음 준비도 손실 1회 취소.

| code | 이름 | activation/module | trigger와 정확한 효과 |
|---|---|---|---|
| `baby-pot.cheer.1` | 응원 넘기기 | choice / `actor_handoff` | 뽀또가 사건을 해결한 뒤 다른 멤버 1명을 지정해 그 멤버의 다음 사건 지원 +1 |
| `baby-pot.cheer.2` | 안심할 길 | map / `safe_choice_hint` | 현재 사건의 안전 선택 비용과 이어지는 노드 종류 공개 |
| `baby-pot.cheer.3` | 응원 자리 바꾸기 | camp / `camp_reconfigure` | 사용 여부를 보존하며 같은 tier 노드 하나 교체 |
| `baby-pot.shelter.1` | 잎우산 | choice / `resolve_guard` | 뽀또가 고른 choice의 `detour` 준비도 -1을 방지 |
| `baby-pot.shelter.2` | 돌아올 화분 | map / `return_anchor` | 현재 camp/entrance를 방문 경로용 1회 귀환점으로 지정 |
| `baby-pot.shelter.3` | 길까지 감싸기 | skill / `signature_retarget` | 새싹 응원의 준비도 보호 대신 다음 미방문 이동 길빛 1을 취소 |
| `baby-pot.curiosity.1` | 잎끝 기웃보기 | map / `node_tag_peek` | 인접 미방문 노드 1개의 종류와 공개 tag 1개 확인 |
| `baby-pot.curiosity.2` | 조그만 틈 | map / `hidden_edge_hint` | 현재/방문 노드의 숨은 간선 방향 1개 확인 |
| `baby-pot.curiosity.3` | 먼저 물어보기 | map / `story_consequence_hint` | 현재 사건 choice 1개의 기록 결과 종류 확인 |

### 4.2 로제온 — `handsome-pot`

뿌리 스킬: `handsome-pot.composed-command` 정돈된 지휘 — 행동자를 다시 고르고 판정 +2.

| code | 이름 | activation/module | trigger와 정확한 효과 |
|---|---|---|---|
| `handsome-pot.command.1` | 차례 정돈 | choice / `actor_handoff` | 로제온 해결 뒤 다른 멤버 1명의 다음 사건 지원 +1 |
| `handsome-pot.command.2` | 역할 재지정 | skill / `signature_retarget` | 행동자 재선택 +2 대신 현재 행동자의 choice 요구 stat을 다른 stat으로 바꾸고 +2는 주지 않음 |
| `handsome-pot.command.3` | 야영 작전회의 | camp / `camp_reconfigure` | 같은 tier 노드 하나를 사용 상태 그대로 교체 |
| `handsome-pot.order.1` | 두 칸 계획 | map / `node_cost_peek` | 거리 2 이내 노드 1개의 길빛 비용·필수 사건 여부 확인 |
| `handsome-pot.order.2` | 열린 길 유지 | move / `map_state_guard` | 장치 전환 때 열린 간선 1개를 다음 전환까지 유지 |
| `handsome-pot.order.3` | 귀환선 정리 | map / `return_anchor` | 현재 camp/entrance를 1회 귀환점으로 지정 |
| `handsome-pot.trust.1` | 결과 공유 | map / `story_consequence_hint` | 다른 멤버가 선택 가능한 choice 1개의 기록 결과 종류 확인 |
| `handsome-pot.trust.2` | 뒤를 맡기기 | choice / `resolve_guard` | 지정한 다른 행동자의 이번 `detour` 준비도 손실 방지 |
| `handsome-pot.trust.3` | 조용한 인계 | choice / `actor_handoff` | 로제온 해결 뒤 아직 이번 사건에 행동하지 않은 멤버의 다음 사건 지원 +1 |

### 4.3 블루미 — `pretty-pot`

뿌리 스킬: `pretty-pot.scene-change` 무대 전환 — `social|performance` 사건 한 단계 clear.

| code | 이름 | activation/module | trigger와 정확한 효과 |
|---|---|---|---|
| `pretty-pot.stagecraft.1` | 작은 무대 | choice / `event_tag_flex` | 현재 사건의 `performance` flex choice 1개를 열어 정상 판정 |
| `pretty-pot.stagecraft.2` | 배역 바꾸기 | choice / `choice_stat_flex` | choice 요구 stat을 블루미의 다른 stat 하나로 대체 |
| `pretty-pot.stagecraft.3` | 막이 닫히지 않게 | move / `map_state_guard` | 장치 전환으로 닫힐 열린 간선 1개를 다음 전환까지 유지 |
| `pretty-pot.rapport.1` | 표정 읽기 | map / `story_consequence_hint` | `social|visitor` 사건 choice 1개의 기록 결과 종류 확인 |
| `pretty-pot.rapport.2` | 다음 주인공 | choice / `actor_handoff` | 블루미 해결 뒤 다른 멤버 1명의 다음 사건 지원 +1 |
| `pretty-pot.rapport.3` | 객석으로 건네기 | skill / `signature_retarget` | 자동 clear 대신 다른 멤버가 `social|performance` choice를 정상 판정할 때 지원 +1 |
| `pretty-pot.spotlight.1` | 비추는 꽃잎 | map / `node_tag_peek` | 인접 미방문 노드 종류와 공개 tag 1개 확인 |
| `pretty-pot.spotlight.2` | 무대 뒤 통로 | map / `hidden_edge_hint` | 방문 노드에 붙은 숨은 간선 방향 1개 확인 |
| `pretty-pot.spotlight.3` | 다음 장면 시간표 | map / `node_cost_peek` | 거리 2 이내 노드 길빛 비용·필수 사건 여부 확인 |

### 4.4 가시로 — `tsundere-pot`

뿌리 스킬: `tsundere-pot.thorn-fence` 가시 울타리 — 이번 detour 손실 방지와 안전 경로 공개.

| code | 이름 | activation/module | trigger와 정확한 효과 |
|---|---|---|---|
| `tsundere-pot.guard.1` | 별로 걱정한 건 아냐 | choice / `resolve_guard` | 가시로 choice의 `detour` 준비도 손실 방지 |
| `tsundere-pot.guard.2` | 바깥길부터 봐 | map / `safe_choice_hint` | 현재 사건의 안전 선택 비용과 다음 노드 종류 확인 |
| `tsundere-pot.guard.3` | 네 쪽이나 막아 | skill / `signature_retarget` | 현재 사건 보호 대신 지정한 다른 멤버의 다음 사건 `detour` 손실 1회 방지 |
| `tsundere-pot.breakthrough.1` | 가시 틈새 | move / `trail_discount` | 이번 미방문 노드 길빛 비용 -1 |
| `tsundere-pot.breakthrough.2` | 닫히기 전에 | move / `map_state_guard` | 열린 간선 1개를 다음 장치 전환까지 유지 |
| `tsundere-pot.breakthrough.3` | 돌아갈 길은 알아둬 | map / `return_anchor` | 현재 camp/entrance를 1회 귀환점으로 지정 |
| `tsundere-pot.quiet_care.1` | 먼저 확인했을 뿐 | map / `story_consequence_hint` | 다른 멤버의 choice 1개가 남길 기록 결과 종류 확인 |
| `tsundere-pot.quiet_care.2` | 이번만 도와줄게 | choice / `actor_handoff` | 가시로 해결 뒤 지정한 다른 멤버의 다음 사건 지원 +1 |
| `tsundere-pot.quiet_care.3` | 몰래 바꾼 준비 | camp / `camp_reconfigure` | 같은 tier 노드 하나를 사용 상태 그대로 교체 |

### 4.5 시들잎 — `zombie-pot`

뿌리 스킬: `zombie-pot.night-sense` 야간 감각 — `dark|dream` 방 비용 0과 인접 방 1개 공개.

| code | 이름 | activation/module | trigger와 정확한 효과 |
|---|---|---|---|
| `zombie-pot.night_sense.1` | 어둠 속 윤곽 | map / `node_tag_peek` | 인접 미방문 노드 종류·tag 1개 확인, `dark|dream`이면 거리 2까지 허용 |
| `zombie-pot.night_sense.2` | 끊긴 그림자 | map / `hidden_edge_hint` | 현재/방문 노드의 숨은 간선 방향 1개 확인 |
| `zombie-pot.night_sense.3` | 꿈 바깥 감각 | skill / `signature_retarget` | `dark|dream` 비용 0 대신 임의 인접 노드 1개의 종류·tag 공개, 비용은 그대로 |
| `zombie-pot.afterimage.1` | 남은 발자국 | map / `return_anchor` | 현재 camp/entrance를 1회 귀환점으로 지정 |
| `zombie-pot.afterimage.2` | 조금 전의 결말 | map / `story_consequence_hint` | 현재 사건 choice 1개의 기록 결과 종류 확인 |
| `zombie-pot.afterimage.3` | 사라지지 않은 길 | move / `map_state_guard` | 장치 전환 때 열린 간선 1개 유지 |
| `zombie-pot.persistence.1` | 천천히 한 걸음 | move / `trail_discount` | 방문 노드에서 새 분기로 나갈 때 길빛 비용 -1 |
| `zombie-pot.persistence.2` | 아직 괜찮아 | choice / `resolve_guard` | 시들잎 choice의 `detour` 준비도 손실 방지 |
| `zombie-pot.persistence.3` | 쉬었다 다시 | camp / `camp_reconfigure` | 같은 tier 노드 하나를 사용 상태 그대로 교체 |

### 4.6 여우비 — `gumiho-pot`

뿌리 스킬: `gumiho-pot.foxfire-lure` 여우불 유인 — 숨은 연결 개방 또는 수호자 안전 우회 비용 -1.

| code | 이름 | activation/module | trigger와 정확한 효과 |
|---|---|---|---|
| `gumiho-pot.foxfire.1` | 꼬리 끝 불빛 | map / `hidden_edge_hint` | 현재/방문 노드의 숨은 간선 방향 1개 확인 |
| `gumiho-pot.foxfire.2` | 두 갈래 유인 | map / `node_cost_peek` | 거리 2 이내 노드 1개의 비용·필수 사건 여부 확인 |
| `gumiho-pot.foxfire.3` | 불빛 돌려놓기 | skill / `signature_retarget` | 숨은 연결 개방 대신 공개된 깊은 방 1개의 이번 이동 비용 -1 |
| `gumiho-pot.illusion.1` | 다른 얼굴의 사건 | choice / `event_tag_flex` | 현재 사건의 `social|mystery` flex choice 중 하나를 열어 정상 판정 |
| `gumiho-pot.illusion.2` | 시선 돌리기 | choice / `choice_stat_flex` | choice 요구 stat을 여우비의 다른 stat 하나로 대체 |
| `gumiho-pot.illusion.3` | 남겨둔 환영 | move / `map_state_guard` | 장치 전환 때 열린 간선 1개 유지 |
| `gumiho-pot.charm.1` | 속마음 한 조각 | map / `story_consequence_hint` | `social|guardian` choice 1개의 기록 결과 종류 확인 |
| `gumiho-pot.charm.2` | 손끝으로 넘기기 | choice / `actor_handoff` | 여우비 해결 뒤 다른 멤버의 다음 사건 지원 +1 |
| `gumiho-pot.charm.3` | 야영의 다른 이야기 | camp / `camp_reconfigure` | 같은 tier 노드 하나를 사용 상태 그대로 교체 |

### 4.7 그림싹 — `ninja-pot`

뿌리 스킬: `ninja-pot.shadow-scout` 그림자 답사 — 최대 두 칸 앞 노드 종류·비용 공개.

| code | 이름 | activation/module | trigger와 정확한 효과 |
|---|---|---|---|
| `ninja-pot.scout.1` | 낮은 시야 | map / `node_tag_peek` | 인접 미방문 노드 종류·tag 1개 확인 |
| `ninja-pot.scout.2` | 발소리 계산 | map / `node_cost_peek` | 거리 2 이내 노드 비용·필수 사건 여부 확인 |
| `ninja-pot.scout.3` | 벽 너머 선 | map / `hidden_edge_hint` | 거리 1의 방문 노드까지 포함해 숨은 간선 방향 1개 확인 |
| `ninja-pot.mark.1` | 잎 표식 | map / `return_anchor` | 현재 camp/entrance를 1회 귀환점으로 지정 |
| `ninja-pot.mark.2` | 짧은 지름 | move / `trail_discount` | 이번 미방문 이동 비용 -1 |
| `ninja-pot.mark.3` | 사라지지 않는 표식 | move / `map_state_guard` | 장치 전환 때 열린 간선 1개 유지 |
| `ninja-pot.relay.1` | 교대 신호 | choice / `actor_handoff` | 그림싹 해결 뒤 다른 멤버의 다음 사건 지원 +1 |
| `ninja-pot.relay.2` | 정찰 공유 | skill / `signature_retarget` | 두 칸 정보 공개 대신 지정한 다른 멤버가 고를 인접 노드 1개의 종류·비용만 공개 |
| `ninja-pot.relay.3` | 야영 재배치 | camp / `camp_reconfigure` | 같은 tier 노드 하나를 사용 상태 그대로 교체 |

### 4.8 별솔 — `magical-pot`

뿌리 스킬: `magical-pot.leaf-transmute` 별잎 변환 — 현재 장애물 요구 stat을 선택한 stat으로 변경.

| code | 이름 | activation/module | trigger와 정확한 효과 |
|---|---|---|---|
| `magical-pot.transmute.1` | 잎맥 치환 | choice / `choice_stat_flex` | 일반 choice 요구 stat을 별솔의 다른 stat 하나로 대체 |
| `magical-pot.transmute.2` | 장면 재분류 | choice / `event_tag_flex` | 현재 사건의 `puzzle|care` flex choice 하나를 열어 정상 판정 |
| `magical-pot.transmute.3` | 비용으로 바꾸기 | skill / `signature_retarget` | stat 변경 대신 해당 choice를 무판정 준비도 1의 안전 해결로 교체 |
| `magical-pot.starlight.1` | 별잎 관측 | map / `node_tag_peek` | 인접 미방문 노드 종류·tag 1개 확인 |
| `magical-pot.starlight.2` | 고정된 별자리 | move / `map_state_guard` | 열린 간선 1개를 다음 장치 전환까지 유지 |
| `magical-pot.starlight.3` | 빛의 거리표 | map / `node_cost_peek` | 거리 2 이내 노드 비용·필수 사건 여부 확인 |
| `magical-pot.ward.1` | 부드러운 결계 | choice / `resolve_guard` | 별솔 choice의 `detour` 준비도 손실 방지 |
| `magical-pot.ward.2` | 안전식 먼저 | map / `safe_choice_hint` | 안전 선택 비용과 이어지는 노드 종류 확인 |
| `magical-pot.ward.3` | 귀환 별잎 | map / `return_anchor` | 현재 camp/entrance를 1회 귀환점으로 지정 |

### 4.9 설화 — `aloof-pot`

뿌리 스킬: `aloof-pot.specimen-analysis` 표본 분석 — 현재 DC -2와 서사 결과 공개.

| code | 이름 | activation/module | trigger와 정확한 효과 |
|---|---|---|---|
| `aloof-pot.analysis.1` | 수치 대조 | map / `node_cost_peek` | 거리 2 이내 노드 비용·필수 사건 여부 확인 |
| `aloof-pot.analysis.2` | 기준 바꾸기 | choice / `choice_stat_flex` | choice 요구 stat을 설화의 다른 stat 하나로 대체 |
| `aloof-pot.analysis.3` | 결론 먼저 | map / `story_consequence_hint` | 현재 사건 choice 1개의 기록 결과 종류 확인 |
| `aloof-pot.archive.1` | 분류표 | map / `node_tag_peek` | 인접 미방문 노드 종류·tag 1개 확인 |
| `aloof-pot.archive.2` | 누락된 색인 | map / `hidden_edge_hint` | 현재/방문 노드의 숨은 간선 방향 1개 확인 |
| `aloof-pot.archive.3` | 되찾을 서가 | map / `return_anchor` | 현재 camp/entrance를 1회 귀환점으로 지정 |
| `aloof-pot.shared_insight.1` | 관찰 인계 | choice / `actor_handoff` | 설화 해결 뒤 다른 멤버의 다음 사건 지원 +1 |
| `aloof-pot.shared_insight.2` | 대신 읽어주기 | skill / `signature_retarget` | 설화 자신의 DC -2·서사 공개 대신 지정한 다른 행동자의 현재 choice DC -2, 서사 미공개 |
| `aloof-pot.shared_insight.3` | 야영 재분류 | camp / `camp_reconfigure` | 같은 tier 노드 하나를 사용 상태 그대로 교체 |

### 4.10 하루 — `student-pot`

뿌리 스킬: `student-pot.field-organize` 현장 정리 — 성장형 스킬 1회 회복 또는 길빛 2 회복.

| code | 이름 | activation/module | trigger와 정확한 효과 |
|---|---|---|---|
| `student-pot.review.1` | 답안 미리보기 | map / `story_consequence_hint` | 현재 사건 choice 1개의 기록 결과 종류 확인 |
| `student-pot.review.2` | 풀이 바꾸기 | choice / `choice_stat_flex` | choice 요구 stat을 하루의 다른 stat 하나로 대체 |
| `student-pot.review.3` | 고쳐 쓴 연결 | move / `map_state_guard` | 장치 전환 때 열린 간선 1개 유지 |
| `student-pot.field_notes.1` | 현장 분류 | map / `node_tag_peek` | 인접 미방문 노드 종류·tag 1개 확인 |
| `student-pot.field_notes.2` | 두 칸 메모 | map / `node_cost_peek` | 거리 2 이내 노드 비용·필수 사건 여부 확인 |
| `student-pot.field_notes.3` | 돌아갈 쪽지 | map / `return_anchor` | 현재 camp/entrance를 1회 귀환점으로 지정 |
| `student-pot.group_study.1` | 다음 발표자 | choice / `actor_handoff` | 하루 해결 뒤 다른 멤버의 다음 사건 지원 +1 |
| `student-pot.group_study.2` | 정리 나눠주기 | skill / `signature_retarget` | 하루의 회복 대신 지정한 다른 멤버의 사용한 성장형 스킬 1회 회복. 길빛 선택 불가 |
| `student-pot.group_study.3` | 야영 복습 | camp / `camp_reconfigure` | 같은 tier 노드 하나를 사용 상태 그대로 교체 |

## 5. 콘텐츠 제공 범위

노드가 존재해도 실제 사건에서 쓸 곳이 없으면 가짜 선택이다. 콘텐츠 validator는 다음을
강제한다.

- 모든 비-camp 노드는 네 지역 중 최소 3곳, 지역당 일반/수호자 사건 2개 이상에서
  유효한 target을 가진다.
- `event_tag_flex`를 쓰는 모든 지역 사건 파일은 품종별 허용 tag에 맞는
  `flex_choices`를 최소 2개 제공한다.
- `story_consequence_hint` 대상은 경제 보상 수량이 아니라 기록 종류만 노출한다.
- `map_state_guard`는 지도 상태 장치가 없는 기억서고에서도 최소 한 개의 문/수로
  상태 사건에 사용할 수 있어야 한다.
- `return_anchor`는 목표까지 필수 이동 수를 줄이지 않고, 이미 방문한 연결만 따라간다.
- `signature_retarget`은 기본 스킬과 합산되지 않으며 두 결과 중 하나만 action log에
  `effective_effect`로 저장한다.
- 세 갈래 깊은 빌드, 2+1, 1+1+1 빌드 모두 정확히 배분 노드 3회 잠재 사용을 가진다.
  유효 target 부족으로 평균 실제 사용 가능 횟수가 2.1 미만이면 콘텐츠가 실패한다.

## 6. 밸런스 시뮬레이션

각 품종에 다음 5개 빌드를 만들어 지역·난이도별 10,000 seed를 실행한다.

```text
A1+A2+A3, B1+B2+B3, C1+C2+C3, A1+A2+B1, A1+B1+C1
```

측정값과 합격선:

| 지표 | 합격선 |
|---|---:|
| 필수 경로 완주율 | 모든 빌드 100% |
| 평균 최소 이동 수 편차 | 품종 내부·품종 간 10% 이내 |
| 평균 준비도 손실 편차 | 0.5 이내 |
| 노드 실제 사용 가능 횟수 | 평균 2.1~3.0 |
| 특정 노드 선택이 유일한 경제 최적해 | 0건 |
| 한 node가 전체 지도 선택지를 무시하고 목표 직행 | 0건 |
| stage 2 무노드+길잡이 완주 | 100% |

시뮬레이션은 사용자가 언제나 최적 선택을 안다는 가정과 첫 공개 선택만 고르는 가정을
둘 다 실행한다. 전자만 통과하고 후자가 막히면 설명·정보 공개 순서가 실패한 것이다.

## 7. 저장·재배분·마이그레이션

- 저장 요청은 정렬된 `node_codes`, `expected_revision`을 받으며 같은 집합은 같은
  canonical hash를 가진다.
- active run은 시작 당시 node 정의·배분·사용 상태를 snapshot으로 유지한다.
- run 밖 재배분은 무료이며 재화·대기 시간·일일 제한이 없다.
- `camp_reconfigure`는 영구 build를 바꾸지 않고 현재 leg snapshot만 바꾼다.
- node code를 삭제·통합할 때는 `{old_code: new_code|null}` migration map을 제공한다.
  `null`은 포인트를 미배분으로 돌리고 사용자에게 재선택 배지를 표시한다.
- stage가 내려가는 시스템은 없지만 데이터 복구로 stage가 낮아지면 초과 노드를
  임의 선택해 삭제하지 않는다. build를 `needs_reallocation`으로 표시하고 run 시작을
  막되 기본 고유·성장형 스킬은 계속 볼 수 있다.

## 8. 완료 조건

- root 10개와 이 문서의 배분 노드 90개가 전역 unique code로 존재한다.
- 모든 node가 닫힌 module 14개 중 하나, 단일 activation, 단일 stack group을 가진다.
- 표의 정확한 trigger·target·effect가 서버, UI 설명, 스크린리더 문구, action log에
  같은 localization key로 연결된다.
- API가 없는 노드, target이 없는 노드, 두 효과를 합친 노드, 자동 소비되는 노드가 없다.
- 10품종×5빌드×4지역×3난이도 시뮬레이션이 합격한다.
- 콘텐츠 pack과 문서 카탈로그의 canonical JSON hash가 CI에서 일치한다.
