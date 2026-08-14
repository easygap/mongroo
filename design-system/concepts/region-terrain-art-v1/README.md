# 지역 지형 원화 v1

세 지역(`echo_well`, `starlight_seed_vault`, `heartwood_observatory`)의 통합 지형
원화 원본이다. 앱에 들어가는 판본은 `design-system/scripts/import_terrain_art.py`가
1600×900과 모바일 960×540 WebP 두 벌로 만든다.

`*-master.webp`만 저장소에 남긴다. 생성 원본 PNG(장당 1.7~2.0MB)는 무시 목록에
있는데, 오디오처럼 스크립트로 같은 바이트를 되살릴 수 없어서 마스터를 남기되
용량이 큰 PNG는 빼는 절충이다. 마스터는 화질 95·원본 해상도라 다시 들여오기에
충분하다.

## 이 그림은 통행 데이터의 원본이기도 하다

캐릭터가 이 지형 위를 직접 걷는다. `design-system/scripts/build_walk_masks.py`가
여기 그려진 길을 80×45 격자로 읽어 앱의 통행 마스크를 만들기 때문에, **지형을
다시 뽑으면 반드시 그 생성기를 다시 돌려야 한다.** 안 돌리면 캐릭터가 없어진 길
위를 걷는다. 지켜야 할 조건은 `design-system/EXPEDITION_ASSET_PRODUCTION.md`에
적어 두었다.
