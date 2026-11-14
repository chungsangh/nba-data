# nba-data

An NBA analytics engineering project built the way a 10-person data team would build it:
**dbt + MetricFlow** on DuckDB/MotherDuck, medallion layers (bronze → silver → gold), governed
metrics, and CI that lets many people change models safely.

The data is real and refreshes daily: ESPN play-by-play, box scores and schedules, republished by
[sportsdataverse-data](https://github.com/sportsdataverse/sportsdataverse-data).

> Status: **Phase 5, team-scale CI and governance.** All planned phases are complete.
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
| [`orchestration/`](orchestration/) | Airflow DAGs (Cosmos), in their own environment. DAG integrity tests. |
| [`docs/adr/`](docs/adr/) | Architecture decision records: why each choice was made. |
| [`scripts/`](scripts/) | Metrics catalog generator with governance rules, known-answer metric checks. |
| [`STYLE_GUIDE.md`](STYLE_GUIDE.md) | Layer rules, naming, SQL style, testing standards. |
| [`METRICS.md`](METRICS.md) | Every metric: definition, owner, tier. Generated. |

## Data model

| Layer | Models | Highlights |
|---|---|---|
| **Bronze** | `stg_espn__plays`, `stg_espn__games`, `stg_espn__player_boxscores`, `stg_espn__team_boxscores` | Renamed and typed, UTC times, sentinel values nulled, empty placeholder rows dropped. |
| **Silver** | `int_plays_sequenced`, `int_possessions_summarized`, `int_shots_located`, `int_games_classified`, `int_players_latest` | Chronological play order, possessions built from play-by-play, shot distance and zone measured to the basket each team attacked that half. |
| **Gold** | `fct_team_games`, `fct_player_games`, `fct_possessions`, `fct_shots`; `dim_games`, `dim_teams`, `dim_players` (type 2), `dim_date` | Enforced contracts, relationship tests to every dimension. `fct_shots` is a microbatch incremental model, `fct_possessions` a lookback incremental model ([ADR 0003](docs/adr/0003-incremental-models-and-history.md)). |

A [`play_type_categories`](transform/seeds/play_type_categories.csv) seed classifies all 136 ESPN
play types; a `schema_drift` test warns when ESPN introduces a new one.

Sanity check on the possession builder across 2025-26: 14.5 seconds per possession and 114.7 points
per 100 possessions, and possessions after a turnover are the fastest and most efficient.

## Semantic layer

MetricFlow semantic models on every gold fact, with 29 published metrics (26 certified, 3
experimental), each with an owner and a tier. The full list is in **[METRICS.md](METRICS.md)**,
generated from the YAML.

```bash
make metrics M=offensive_rating,defensive_rating,net_rating G=team__team_abbreviation
cd transform && uv run mf query --saved-query league_shot_profile
```

2025-26 regular season, from the `team_ratings_by_season` saved query:

| Team | Win % | Off. rating | Def. rating | Net rating |
|---|---|---|---|---|
| OKC | .780 | 118.5 | 107.2 | +11.3 |
| SA | .756 | 119.4 | 111.2 | +8.3 |
| DET | .732 | 117.9 | 109.7 | +8.2 |

And the shot-value curve from `league_shot_profile`: 1.36 points per shot at the rim, 1.14 on
corner threes, 1.04 on above-the-break threes, 0.83 from mid-range.

How metrics are governed (owners, tiers, certified-can't-depend-on-experimental, known-answer
tests) is in [CONTRIBUTING.md](CONTRIBUTING.md#changing-metrics).

## Orchestration

Airflow 3 DAGs in [`orchestration/`](orchestration/), with
[Astronomer Cosmos](https://github.com/astronomer/astronomer-cosmos) turning every dbt model,
seed, snapshot and test into its own Airflow task:

```
nba_daily   ingest current season ─► reset changed incremental models ─► dbt (51 tasks: model ─► its tests; cross-model tests wait for all parents)
                                 ─► MetricFlow validation + known-answer metric tests ─► source freshness
nba_backfill  reload chosen seasons ─► dbt build --full-refresh ─► metric checks   (manual, with params)
```

- **Prod** runs on a GitHub Actions schedule ([`prod.yml`](.github/workflows/prod.yml)) that
  executes the same DAG headless against MotherDuck, saves the prod dbt manifest, and opens a
  `prod-failure` issue when a task fails. Why not hosted Airflow: [ADR 0004](docs/adr/0004-orchestration-airflow-on-actions.md).
  Setting up the MotherDuck token safely: [docs/prod-setup.md](docs/prod-setup.md).
- **Locally**: `make airflow-setup` once, then `make airflow-ui` for the Airflow UI or
  `make airflow-run` to run `nba_daily` headless against your local DuckDB.
- **Docs**: [`docs.yml`](.github/workflows/docs.yml) publishes the dbt docs site (lineage, model
  and column docs) to GitHub Pages on every merge to `main`.

## Quality gates

Every commit (pre-commit) and every pull request (GitHub Actions) runs:

- **ruff** for Python, **SQLFluff** for SQL (rendered through dbt).
- **dbt-checkpoint**: every model documented, has a properties file and tests; model names follow
  the layer convention; every source has freshness rules.
- **pytest** for the ingestion code, metric governance rules, and Airflow DAG integrity (DAGs
  import, every task has an owner, retries and failure alerting; Cosmos renders every model).
- **`dbt build`** into a schema owned by that PR (`ci_pr_<n>_*`): models, **unit tests** for
  transformation logic (play ordering and possession numbering, shot geometry, label cleanup),
  data tests, and **contracts** on every gold model.
- **Reconciliation tests**: box-score points must match play-by-play scoring (fails if more than 10
  team-games disagree), every completed game has exactly two mirrored team rows, and
  play-by-play possessions stay close to the box-score estimate.
- **Semantic layer**: `mf validate-configs` against the warehouse; metric governance rules and an
  up-to-date METRICS.md; **known-answer metric tests** that compare certified saved queries with
  independently written SQL (a deliberately wrong eFG% formula is caught).
- **Source freshness**, reported without blocking unrelated PRs.

### For a team

- **Slim CI**: PRs build only changed models and everything downstream, reading the rest from
  `main`'s last CI build (no warehouse credentials in PRs), then clone unchanged models so every
  check sees a complete project. A one-model change builds 10 nodes instead of 137.
- **Data diff on every PR**: a [Recce](https://github.com/DataRecce/recce) comment with row count
  and schema changes and the lineage of what changed.
- **Breaking-change guard**: removing or retyping a column of a contracted model without a new
  model version fails CI unless a reviewer adds `approved-breaking-change`. Example migration:
  `dim_games` v1 → v2.
- **Ownership enforced by dbt**: groups `platform` and `game_analytics`; silver models are private
  to their group, gold is public. [CODEOWNERS](.github/CODEOWNERS) routes reviews the same way.
- **dbt-project-evaluator** fails CI on new structure problems (layer skipping, missing PK tests,
  undocumented public models); [approved exceptions](transform/seeds/dbt_project_evaluator_exceptions.csv)
  carry a reason.

Every PR gets four checks: **Lint & unit tests**, **dbt build** and **Project structure**
(required), and **Data diff** (advisory). Design and trade-offs:
[ADR 0005](docs/adr/0005-team-scale-ci-and-governance.md).

Known upstream data issues are tracked as warning-level tests tagged `known_issue`, so they stay
visible on every run. Example: ESPN's `sequence_number` order made the running score go backwards
~4,600 times in two seasons; silver orders by `game_play_number` instead, which leaves 24 genuine
score corrections.

## Roadmap

1. **Foundation** — ingestion, bronze, style guide, pre-commit, CI. ✅
2. **Bronze/silver/gold** — all sources, play ordering, possessions, shot zones; gold facts and
   dimensions with contracts; incremental models with lookback for stat corrections; player history
   snapshot. ✅ (On-court lineup stints are deferred to a follow-up.)
3. **Semantic layer** — MetricFlow semantic models and metrics (offensive/defensive/net rating,
   pace, eFG%, TS%, season-to-date and rolling metrics), saved queries, metric ownership and tiers. ✅
4. **Orchestration & prod** — Airflow + Astronomer Cosmos DAGs, MotherDuck prod, scheduled runs,
   backfills, alerts, dbt docs site. ✅
5. **Team-scale CI & governance** — Slim CI with `state:modified+ --defer`, Recce data diffs on PRs,
   dbt-project-evaluator, CODEOWNERS, model access and groups, versioned gold models,
   breaking-change guard. ✅

## Data and attribution

Data comes from ESPN via the sportsdataverse project. This repository contains code only; no raw
data is committed. It is a non-commercial portfolio project.
