from datetime import timedelta

import sqlalchemy as sa

from app.core.timeutil import utcnow
from app.models.enums import AnalysisStatus, PlantStatus
from app.models.mood import MoodEntry
from app.models.plant import Plant, PlantSpecies
from app.services.plants import build_emotion_profile
from tests.conftest import auth_headers, signup


async def test_harvest_snapshots_only_lifecycle_emotions_with_source_precedence(
    client, session_factory
):
    tokens = await signup(client)
    user_id = tokens["user"]["id"]
    now = utcnow()
    planted_at = now - timedelta(days=10)

    async with session_factory() as db:
        plant = await db.scalar(
            sa.select(Plant).where(
                Plant.user_id == user_id, Plant.status == PlantStatus.ACTIVE
            )
        )
        plant.exp = 1000
        plant.planted_at = planted_at

        def mood(days, level, **values):
            recorded_at = now + timedelta(days=days)
            return MoodEntry(
                user_id=user_id,
                local_date=recorded_at.date(),
                recorded_at_utc=recorded_at,
                mood_level=level,
                emotion_tags=[],
                content="식물과 함께 보낸 하루를 적은 일기",
                **values,
            )

        db.add_all(
            [
                # 생애 이전/미래 기록은 제외된다.
                mood(
                    -11, 5, ai_emotion="기쁨", analysis_status=AnalysisStatus.SUCCEEDED
                ),
                mood(1, 1, ai_emotion="당황", analysis_status=AnalysisStatus.SUCCEEDED),
                # 교정값과 숨김 설정은 성장 분기에 관여하지 않는다.
                mood(
                    -8,
                    1,
                    ai_emotion_override="분노",
                    ai_emotion="기쁨",
                    analysis_status=AnalysisStatus.SUCCEEDED,
                    ai_label_hidden=True,
                ),
                mood(
                    -7, 3, ai_emotion="슬픔", analysis_status=AnalysisStatus.SUCCEEDED
                ),
                # 숨긴 raw 분석은 쓰고 실패 분석은 제외한다.
                mood(
                    -6,
                    1,
                    ai_emotion="슬픔",
                    analysis_status=AnalysisStatus.SUCCEEDED,
                    ai_label_hidden=True,
                ),
                mood(-5, 1, ai_emotion="분노", analysis_status=AnalysisStatus.FAILED),
                mood(
                    -4, 3, ai_emotion="분노", analysis_status=AnalysisStatus.SUCCEEDED
                ),
                mood(
                    -3, 5, ai_emotion="슬픔", analysis_status=AnalysisStatus.SUCCEEDED
                ),
            ]
        )
        await db.commit()
        plant_id = plant.id

    harvested = await client.post(
        f"/plants/{plant_id}/harvest", headers=auth_headers(tokens, idem=True)
    )
    assert harvested.status_code == 200, harvested.text
    result = harvested.json()["plant"]
    assert result["final_form"] == "rainy"
    assert result["museum_featured"] is False
    assert result["emotion_profile"]["total"] == 5
    assert result["emotion_profile"]["version"] == 3
    assert result["emotion_profile"]["weights"] == {
        "joy": 1.0,
        "sadness": 3.0,
        "anger": 1.0,
        "anxiety": 0.0,
        "surprise": 0.0,
        "mixed": 0.0,
    }
    assert result["emotion_profile"]["unavailable_count"] == 1
    assert result["emotion_profile"]["counts"] == {
        "joy": 1,
        "sadness": 3,
        "anger": 1,
        "anxiety": 0,
        "surprise": 0,
        "mixed": 0,
    }

    # 수확 뒤 원본 기록이 바뀌어도 박물관 표본의 모습은 고정된다.
    async with session_factory() as db:
        await db.execute(
            sa.update(MoodEntry)
            .where(MoodEntry.user_id == user_id)
            .values(ai_emotion_override="기쁨")
        )
        await db.commit()

    museum = await client.get("/plants/museum", headers=auth_headers(tokens))
    assert museum.status_code == 200
    item = museum.json()["items"][0]
    assert item["id"] == plant_id
    assert item["final_form"] == "rainy"
    assert item["emotion_profile"] == result["emotion_profile"]

    gallery = await client.get("/plants?status=harvested", headers=auth_headers(tokens))
    assert gallery.json()["items"][0]["final_form"] == "rainy"


async def test_museum_recent_featured_modes_and_ten_item_limit(client, session_factory):
    tokens = await signup(client)
    user_id = tokens["user"]["id"]
    now = utcnow()
    profile = build_emotion_profile(())

    async with session_factory() as db:
        species_id = await db.scalar(
            sa.select(PlantSpecies.id).where(PlantSpecies.code == "basic_sprout")
        )
        plants = [
            Plant(
                user_id=user_id,
                species_id=species_id,
                name=f"표본 {index}",
                exp=1000,
                status=PlantStatus.HARVESTED,
                planted_at=now - timedelta(days=30 + index),
                harvested_at=now - timedelta(minutes=11 - index),
                final_form="mosaic",
                emotion_profile=profile,
            )
            for index in range(11)
        ]
        db.add_all(plants)
        await db.commit()
        plant_ids = [plant.id for plant in plants]

    recent = await client.get("/plants/museum", headers=auth_headers(tokens))
    assert recent.status_code == 200
    assert recent.json()["mode"] == "recent"
    assert recent.json()["limit"] == 10
    assert recent.json()["max_featured"] == 10
    assert len(recent.json()["items"]) == 10
    assert [item["id"] for item in recent.json()["items"]] == list(reversed(plant_ids))[
        :10
    ]

    limited = await client.get("/plants/museum?limit=3", headers=auth_headers(tokens))
    assert len(limited.json()["items"]) == 3
    invalid = await client.get("/plants/museum?limit=11", headers=auth_headers(tokens))
    assert invalid.status_code == 422

    for index, plant_id in enumerate(plant_ids[:10], start=1):
        selected = await client.patch(
            f"/plants/{plant_id}/museum",
            json={"is_featured": True},
            headers=auth_headers(tokens),
        )
        assert selected.status_code == 200, selected.text
        assert selected.json()["featured_count"] == index
        assert selected.json()["plant"]["museum_featured"] is True

    overflow = await client.patch(
        f"/plants/{plant_ids[10]}/museum",
        json={"is_featured": True},
        headers=auth_headers(tokens),
    )
    assert overflow.status_code == 409
    assert overflow.json()["code"] == "MUSEUM_FEATURED_LIMIT"
    assert overflow.json()["details"] == {"max_featured": 10}

    featured = await client.get(
        "/plants/museum?mode=featured", headers=auth_headers(tokens)
    )
    assert featured.status_code == 200
    assert featured.json()["mode"] == "featured"
    assert len(featured.json()["items"]) == 10
    assert all(item["museum_featured"] for item in featured.json()["items"])

    removed = await client.patch(
        f"/plants/{plant_ids[0]}/museum",
        json={"is_featured": False},
        headers=auth_headers(tokens),
    )
    assert removed.status_code == 200
    assert removed.json()["featured_count"] == 9
    replacement = await client.patch(
        f"/plants/{plant_ids[10]}/museum",
        json={"is_featured": True},
        headers=auth_headers(tokens),
    )
    assert replacement.status_code == 200
    assert replacement.json()["featured_count"] == 10


async def test_museum_selection_rejects_active_and_foreign_plants(client):
    owner = await signup(client)
    stranger = await signup(client)
    active = await client.get("/plants/me", headers=auth_headers(owner))
    plant_id = active.json()["plant"]["id"]

    not_harvested = await client.patch(
        f"/plants/{plant_id}/museum",
        json={"is_featured": True},
        headers=auth_headers(owner),
    )
    assert not_harvested.status_code == 409
    assert not_harvested.json()["code"] == "PLANT_NOT_HARVESTED"

    forbidden = await client.patch(
        f"/plants/{plant_id}/museum",
        json={"is_featured": True},
        headers=auth_headers(stranger),
    )
    assert forbidden.status_code == 403
    assert forbidden.json()["code"] == "FORBIDDEN"
