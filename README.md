# nba-data

An NBA analytics engineering project built the way a 10-person data team would build it:
**dbt + MetricFlow** on DuckDB/MotherDuck, medallion layers (bronze → silver → gold), governed
metrics, and CI that lets many people change models safely.

The data is real and refreshes daily: ESPN play-by-play, box scores and schedules, republished by
[sportsdataverse-data](https://github.com/sportsdataverse/sportsdataverse-data).

> Status: **Phase 1, foundation.** Ingestion, the first bronze model, linting and CI are in place.
> See the [roadmap](#roadmap) and the full [project plan](docs/project-plan.md).

## Quick start

Needs Python 3.12 and [uv](https://docs.astral.sh/uv/). No accounts, no cloud costs.

```bash
make setup                       # Python deps, dbt packages, git hooks
make ingest SEASONS="2026 2027"  # 2025-26 and 2026-27 seasons into data/nba.duckdb (~30 MB)
make build                       # dbt models + unit tests + data tests
```

Or open the repo in a GitHub Codespace / devcontainer, which runs all three for you.
`make help` lists every command.

## How it fits together

```
sportsdataverse parquet ──► ingestion/ (Python) ──► raw schema ──► dbt: bronze ─► silver ─► gold ─► MetricFlow
   (daily, per season)       idempotent loads,        lineage        views         tables     contracts   metrics
                             schema-drift handling     columns
```

| Folder | What's there |
|---|---|
| [`ingestion/`](ingestion/) | Downloads season files, replaces one season per load in a transaction, adds lineage columns, logs every load, handles upstream schema drift. Tested with pytest. |
| [`transform/`](transform/) | The dbt project. `models/bronze`, `silver`, `gold`, `semantic`. |
| [`docs/adr/`](docs/adr/) | Architecture decision records: why each choice was made. |
| [`STYLE_GUIDE.md`](STYLE_GUIDE.md) | Layer rules, naming, SQL style, testing standards. |

## Quality gates

Every commit (pre-commit) and every pull request (GitHub Actions) runs:

- **ruff** for Python, **SQLFluff** for SQL (rendered through dbt).
- **dbt-checkpoint**: every model documented, has a properties file and tests; model names follow
  the layer convention; every source has freshness rules.
- **pytest** for the ingestion code.
- **`dbt build`** into a schema owned by that PR (`ci_pr_<n>_*`): models, **unit tests** for
  transformation logic, and data tests.
- **Source freshness**, reported without blocking unrelated PRs.

Known upstream data issues are tracked as warning-level tests tagged `known_issue` (for example,
ESPN's play order sometimes makes the running score go backwards), so they stay visible on every run
until the silver layer resolves them.

## Roadmap

1. **Foundation** — ingestion, bronze, style guide, pre-commit, CI. ✅
2. **Bronze/silver/gold** — all sources, play ordering, possessions, lineups, shot zones; gold facts
   and dimensions with contracts; incremental models with lookback for stat corrections; player
   history snapshots.
3. **Semantic layer** — MetricFlow semantic models and metrics (offensive/defensive/net rating,
   pace, eFG%, TS%, season-to-date and rolling metrics), saved queries, metric ownership and tiers.
4. **Orchestration & prod** — Airflow + Astronomer Cosmos DAGs, MotherDuck prod, scheduled runs,
   backfills, alerts, dbt docs site.
5. **Team-scale CI & governance** — Slim CI with `state:modified+ --defer`, Recce data diffs on PRs,
   dbt-project-evaluator, CODEOWNERS, model access and groups, versioned gold models,
   breaking-change guard.

## Data and attribution

Data comes from ESPN via the sportsdataverse project. This repository contains code only; no raw
data is committed. It is a non-commercial portfolio project.
