# ADR 0002: Ingest sportsdataverse parquet releases, replacing one season per load

- Status: accepted
- Date: 2026-11-13

## Context

We need NBA play-by-play, box scores and schedules that refresh daily and can be fetched from
GitHub Actions for free.

- `stats.nba.com` (used by `nba_api`) blocks cloud IP ranges, including GitHub Actions.
- `cdn.nba.com` returned HTTP 403 to plain requests; getting around bot protection is not acceptable.
- balldontlie's free tier covers teams/players/games only; stats and play-by-play are paid.
- [sportsdataverse-data](https://github.com/sportsdataverse/sportsdataverse-data) republishes ESPN
  data as one parquet file per season, refreshed daily (~07:30 ET), as plain GitHub release assets.

## Decision

- Source: sportsdataverse-data releases (`espn_nba_pbp`, `espn_nba_schedules`,
  `espn_nba_player_boxscores`, `espn_nba_team_boxscores`, `espn_nba_rosters`).
- Rosters are a point-in-time list (who is on each team today). Each load replaces it, and the
  `snap_players` snapshot turns the daily changes into history.
- Each load **replaces one season** of one dataset in a single transaction. Re-runs and backfills
  are idempotent; upstream stat corrections are picked up on the next daily load.
- Every row gets lineage columns: `_load_id`, `_loaded_at`, `_source_url`,
  `_source_published_at`. `raw._load_log` keeps one row per load with row counts.
- **Schema drift:** new upstream columns are added to the raw table automatically (older seasons
  get NULL) and logged as a warning. Bronze models select columns explicitly, so a new column never
  reaches consumers until someone adds it on purpose.
- Raw data is never committed to git. The publisher's data originates from ESPN; this repo
  holds code only, and credits the source.

## Consequences

- Granularity of "incremental" is a season file per day (a few MB in-season), which is cheap.
  Row-level incrementality starts in dbt (silver/gold incremental models).
- We depend on a community publisher. If it stops, the loader's dataset registry
  (`ingestion/sources.py`) is the single place to point at a new source.
