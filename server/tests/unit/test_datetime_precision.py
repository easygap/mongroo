from sqlalchemy.dialects import mysql

from app.models.mood import MoodEntry
from app.models.plant import Plant


def test_plant_lifecycle_timestamps_keep_mysql_microseconds():
    dialect = mysql.dialect()
    columns = (
        MoodEntry.__table__.c.recorded_at_utc,
        Plant.__table__.c.planted_at,
        Plant.__table__.c.harvested_at,
        Plant.__table__.c.branch_decided_at,
    )

    assert all(column.type.dialect_impl(dialect).fsp == 6 for column in columns)
