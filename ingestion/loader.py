"""Download sportsdataverse parquet files and load them into the warehouse ``raw`` schema.

Design choices (see docs/adr/0002-ingestion.md):

* **Idempotent per (dataset, season).** A load replaces every row of that season in one transaction,
  so re-running a day, or a backfill, never duplicates rows.
* **Lineage columns.** Every row carries ``_load_id``, ``_loaded_at``, ``_source_url`` and
  ``_source_published_at`` (the publisher's own refresh time), which drives dbt source freshness.
* **Load log.** ``raw._load_log`` records one row per load with row counts, for auditing.
* **Warehouse-agnostic target.** The target is any DuckDB connection string, so the same code
  writes to a local file in dev/CI and to MotherDuck (``md:<db>``) in prod.
"""

from __future__ import annotations

import json
import logging
import tempfile
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import duckdb
import httpx
from tenacity import retry, retry_if_exception_type, stop_after_attempt, wait_exponential

from ingestion.sources import Dataset

log = logging.getLogger(__name__)

RAW_SCHEMA = "raw"
HTTP_TIMEOUT = httpx.Timeout(60.0, connect=15.0)


class SourceFileNotFound(Exception):
    """The publisher has no file for this dataset/season (e.g. a season that has not started)."""


@dataclass(frozen=True)
class LoadResult:
    dataset: str
    season: int
    rows_loaded: int
    rows_replaced: int
    source_published_at: datetime | None


@retry(
    retry=retry_if_exception_type((httpx.TransportError, httpx.HTTPStatusError)),
    stop=stop_after_attempt(4),
    wait=wait_exponential(multiplier=2, max=30),
    reraise=True,
)
def _get(client: httpx.Client, url: str) -> httpx.Response:
    response = client.get(url)
    if response.status_code == 404:
        raise SourceFileNotFound(url)
    response.raise_for_status()
    return response


def fetch_published_at(client: httpx.Client, dataset: Dataset) -> datetime | None:
    """Return the publisher's last refresh time for a dataset, or None if unavailable."""
    try:
        payload = json.loads(_get(client, dataset.timestamp_url).content)
    except (SourceFileNotFound, json.JSONDecodeError, httpx.HTTPError):
        log.warning("No usable timestamp.json for %s", dataset.release_tag)
        return None
    return parse_published_at(payload.get("last_updated"))


def parse_published_at(value: str | None) -> datetime | None:
    """Parse the publisher's timestamp, e.g. ``"2026-11-13 07:32:12 EST"``, into UTC."""
    if not value:
        return None

    stamp, _, tz_abbrev = value.rpartition(" ")
    # The publisher writes US Eastern time with an EST/EDT suffix.
    if tz_abbrev not in {"EST", "EDT"}:
        log.warning("Unexpected timestamp format: %r", value)
        return None
    naive = datetime.strptime(stamp, "%Y-%m-%d %H:%M:%S")
    return naive.replace(tzinfo=ZoneInfo("America/New_York")).astimezone(UTC)


def download(client: httpx.Client, url: str, dest: Path) -> Path:
    dest.write_bytes(_get(client, url).content)
    return dest


def _ensure_raw_schema(con: duckdb.DuckDBPyConnection) -> None:
    con.execute(f"create schema if not exists {RAW_SCHEMA}")
    con.execute(
        f"""
        create table if not exists {RAW_SCHEMA}._load_log (
            load_id varchar,
            dataset varchar,
            season integer,
            source_url varchar,
            source_published_at timestamptz,
            loaded_at timestamptz,
            rows_loaded bigint,
            rows_replaced bigint
        )
        """
    )


def _table_exists(con: duckdb.DuckDBPyConnection, table: str) -> bool:
    return bool(
        con.execute(
            "select count(*) from information_schema.tables "
            "where table_schema = ? and table_name = ?",
            [RAW_SCHEMA, table],
        ).fetchall()[0][0]
    )


def _add_new_columns(con: duckdb.DuckDBPyConnection, table: str, parquet_path: Path) -> list[str]:
    """Schema evolution: add columns the publisher introduced since the table was created.

    Older seasons get NULL for the new column. Added columns are logged so a reviewer can decide
    whether bronze models should expose them. Dropped upstream columns need no action: they
    simply arrive as NULL for the new season, which bronze-layer not_null tests will surface.
    """
    existing = {
        r[0]
        for r in con.execute(
            "select column_name from information_schema.columns "
            "where table_schema = ? and table_name = ?",
            [RAW_SCHEMA, table],
        ).fetchall()
    }
    incoming = con.execute(
        "select column_name, column_type from (describe select * from read_parquet(?))",
        [str(parquet_path)],
    ).fetchall()
    added = []
    for name, col_type in incoming:
        if name not in existing:
            con.execute(f'alter table {RAW_SCHEMA}.{table} add column "{name}" {col_type}')
            added.append(name)
    if added:
        log.warning("Schema drift in %s: added columns %s", table, ", ".join(added))
    return added


def load_parquet(
    con: duckdb.DuckDBPyConnection,
    dataset: Dataset,
    season: int,
    parquet_path: Path,
    source_published_at: datetime | None,
) -> LoadResult:
    """Replace one season of ``dataset`` in the raw schema with the rows in ``parquet_path``."""
    _ensure_raw_schema(con)
    table = f"{RAW_SCHEMA}.{dataset.name}"
    load_id = str(uuid.uuid4())
    loaded_at = datetime.now(UTC)
    select_new = """
        select
            *,
            ?::varchar as _load_id,
            ?::timestamptz as _loaded_at,
            ?::varchar as _source_url,
            ?::timestamptz as _source_published_at
        from read_parquet(?)
    """
    params = [load_id, loaded_at, dataset.url(season), source_published_at, str(parquet_path)]

    con.execute("begin transaction")
    try:
        rows_replaced = 0
        if not _table_exists(con, dataset.name):
            con.execute(f"create table {table} as {select_new} limit 0", params)
        else:
            rows_replaced = con.execute(
                f"select count(*) from {table} where season = ?", [season]
            ).fetchall()[0][0]
            con.execute(f"delete from {table} where season = ?", [season])
            _add_new_columns(con, dataset.name, parquet_path)
        # BY NAME tolerates upstream column reordering and columns missing from older seasons.
        con.execute(f"insert into {table} by name {select_new}", params)
        rows_loaded = con.execute(
            f"select count(*) from {table} where season = ?", [season]
        ).fetchall()[0][0]
        con.execute(
            f"insert into {RAW_SCHEMA}._load_log values (?, ?, ?, ?, ?, ?, ?, ?)",
            [
                load_id,
                dataset.name,
                season,
                dataset.url(season),
                source_published_at,
                loaded_at,
                rows_loaded,
                rows_replaced,
            ],
        )
        con.execute("commit")
    except Exception:
        con.execute("rollback")
        raise

    return LoadResult(dataset.name, season, rows_loaded, rows_replaced, source_published_at)


def ensure_database(database: str) -> None:
    """MotherDuck databases must exist before connecting to them by name; create on first run."""
    if not database.startswith("md:"):
        return
    name = database.removeprefix("md:").split("?")[0]
    if name:
        with duckdb.connect("md:") as con:
            con.execute(f'create database if not exists "{name}"')


def ingest(
    datasets: list[Dataset],
    seasons: list[int],
    database: str,
    client: httpx.Client | None = None,
) -> list[LoadResult]:
    """Download and load every (dataset, season) pair into ``database``."""
    ensure_database(database)
    own_client = client is None
    client = client or httpx.Client(timeout=HTTP_TIMEOUT, follow_redirects=True)
    results: list[LoadResult] = []
    try:
        with duckdb.connect(database) as con, tempfile.TemporaryDirectory() as tmp:
            for dataset in datasets:
                published_at = fetch_published_at(client, dataset)
                for season in seasons:
                    path = Path(tmp) / dataset.file_name(season)
                    try:
                        download(client, dataset.url(season), path)
                    except SourceFileNotFound:
                        log.warning("Skipping %s season %s: not published", dataset.name, season)
                        continue
                    result = load_parquet(con, dataset, season, path, published_at)
                    log.info(
                        "Loaded %s season %s: %s rows (replaced %s)",
                        result.dataset,
                        result.season,
                        result.rows_loaded,
                        result.rows_replaced,
                    )
                    results.append(result)
    finally:
        if own_client:
            client.close()
    return results
