from datetime import UTC, date, datetime
from pathlib import Path

import duckdb
import pytest

from ingestion.cli import current_season
from ingestion.loader import load_parquet, parse_published_at
from ingestion.sources import DATASETS

PLAYS = DATASETS["espn_nba_plays"]


def _write_parquet(path: Path, rows: list[tuple[str, int]]) -> Path:
    con = duckdb.connect()
    values = ", ".join(f"('{play_id}', {season})" for play_id, season in rows)
    con.execute(
        f"copy (select * from (values {values}) t(id, season)) to '{path}' (format parquet)"
    )
    return path


@pytest.fixture
def con():
    with duckdb.connect(":memory:") as connection:
        yield connection


def test_load_creates_table_and_lineage_columns(con, tmp_path):
    path = _write_parquet(tmp_path / "s.parquet", [("a", 2027), ("b", 2027)])
    result = load_parquet(con, PLAYS, 2027, path, None)

    assert result.rows_loaded == 2
    assert result.rows_replaced == 0
    cols = {r[0] for r in con.execute("describe raw.espn_nba_plays").fetchall()}
    assert {"_load_id", "_loaded_at", "_source_url", "_source_published_at"} <= cols


def test_reload_is_idempotent_and_only_touches_its_season(con, tmp_path):
    load_parquet(con, PLAYS, 2026, _write_parquet(tmp_path / "a.parquet", [("x", 2026)]), None)
    load_parquet(con, PLAYS, 2027, _write_parquet(tmp_path / "b.parquet", [("a", 2027)]), None)
    # The publisher re-issues 2027 with one more play: reload replaces, never duplicates.
    path = _write_parquet(tmp_path / "c.parquet", [("a", 2027), ("b", 2027)])
    result = load_parquet(con, PLAYS, 2027, path, None)

    assert result.rows_replaced == 1
    counts = dict(
        con.execute("select season, count(*) from raw.espn_nba_plays group by 1").fetchall()
    )
    assert counts == {2026: 1, 2027: 2}
    assert con.execute("select count(*) from raw._load_log").fetchall()[0][0] == 3


def test_new_upstream_column_is_added_not_fatal(con, tmp_path):
    load_parquet(con, PLAYS, 2026, _write_parquet(tmp_path / "a.parquet", [("x", 2026)]), None)
    path = tmp_path / "b.parquet"
    duckdb.connect().execute(
        f"copy (select 'y' as id, 2027 as season, 'new' as shot_zone) to '{path}' (format parquet)"
    )
    load_parquet(con, PLAYS, 2027, path, None)

    rows = con.execute("select id, shot_zone from raw.espn_nba_plays order by id").fetchall()
    assert rows == [("x", None), ("y", "new")]


def test_parse_published_at_converts_eastern_to_utc():
    assert parse_published_at("2026-11-13 07:32:12 EST") == datetime(
        2026, 11, 13, 12, 32, 12, tzinfo=UTC
    )
    assert parse_published_at("garbage") is None
    assert parse_published_at(None) is None


@pytest.mark.parametrize(
    ("today", "season"),
    [(date(2026, 11, 13), 2027), (date(2027, 6, 10), 2027), (date(2027, 8, 1), 2028)],
)
def test_current_season(today, season):
    assert current_season(today) == season
