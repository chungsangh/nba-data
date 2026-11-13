# Public dbt + MetricFlow portfolio repo — plan

## Context
You want a public GitHub repo that proves senior/lead/staff analytics-engineer skills, not just "I can write
staging and mart models". Job posts at that level (Cribl, Twilio GTM, HotelEngine, Juniper Square, Fieldguide,
Pantheon, Chainguard, GitLab handbook) consistently ask for, beyond modeling: **governed metrics / semantic
layer**, **standards enforced through CI and code review**, **contract-based architecture that lets many
people work safely**, and **orchestration/ops ownership**. The repo should read like the analytics codebase of
a 10-person data team, run end to end for $0, and be cloneable by a reviewer in under 5 minutes.

Decisions: public data, **NBA/basketball** is the leading topic (final pick at build start; alternates in
Section 2), dbt Core 1.x pinned + open-source MetricFlow with a dbt Core v2 (Fusion) compatibility job,
**Airflow** for orchestration, explicit **bronze/silver/gold** layers with a gold mart layer, $0 budget.
Out of scope for now: dbt Mesh/multi-project, BI / consumer app.

---

## 1. Skills the repo must demonstrate

| # | Skill area | What a reviewer should see |
|---|---|---|
| A | **Medallion modeling** | bronze (raw + 1:1 staging) → silver (cleaned, conformed, business logic) → **gold marts** (Kimball facts/dims, the only layer consumers and MetricFlow touch); written style guide; naming enforced by tooling |
| B | **Hard modeling patterns** | incremental models (merge + `microbatch` with lookback for late/corrected data), SCD2 snapshots, date spine, timezone handling, dedup of revised source rows, idempotent re-runs |
| C | **Semantic layer (MetricFlow)** | semantic models on gold marts, entities, time-grained dimensions; simple, ratio, derived, cumulative (and conversion where it fits) metrics; saved queries + exports; `mf validate-configs` / `mf query` in CI |
| D | **Metric governance** | owners, descriptions, certified vs. experimental tiers in `meta`, a generated metrics catalog, metric-change review rules |
| E | **Testing pyramid** | generic + custom data tests, **unit tests** (dbt ≥1.8) on tricky SQL, **contracts** on gold marts, source **freshness**, known-answer tests of metric values (e.g., box-score totals reconcile to official team totals), severity/warn thresholds |
| F | **Team-scale CI/CD** | GitHub Actions: SQLFluff lint, dbt-project-evaluator, dbt-checkpoint pre-commit, **Slim CI** (`state:modified+ --defer` vs prod manifest), unit tests, MetricFlow validation, **Recce** data diff posted on the PR, Fusion compile job |
| G | **Governance for many contributors** | CODEOWNERS per domain, PR template with impact checklist, model `access`/`groups`, **model versions** for a breaking gold change with deprecation date, breaking-contract guard |
| H | **Orchestration (Airflow)** | Airflow DAGs with **Astronomer Cosmos** rendering each dbt model/test as an Airflow task; ingestion → dbt build → freshness → artifacts; retries, SLAs, backfill by date, failure alerts |
| I | **Observability & cost** | models over `run_results.json`/elementary for test history, run time per model, row-count anomalies; short performance note |
| J | **Docs & DX** | dbt docs on GitHub Pages, ADRs, CONTRIBUTING, `Makefile`, devcontainer/Codespaces one-click setup |
| K | **Python where it fits** | ingestion extractors with retries/pagination/rate limits + pytest; a dbt Python model (e.g., Elo team ratings) |

"Staff-level" communication evidence: README explaining *why*, ADRs, a metric-definition RFC merged as a PR,
clean PR history with reviews.

---

## 2. Topic: NBA (leading) + alternates

### NBA — how it maps to the skills
- **Chosen source (verified 2026-11-13): sportsdataverse-data GitHub releases** (MIT repo; data comes from
  ESPN). Parquet per season, refreshed daily ~07:30 ET, downloaded with plain HTTPS from Actions:
  `espn_nba_pbp/play_by_play_{season}.parquet` (2025-26: 642k plays, 1,325 games incl. playoffs, 22 MB;
  2026-27 live through yesterday), `espn_nba_player_boxscores`, `espn_nba_team_boxscores`,
  `espn_nba_schedules` (status, venue, broadcast), `espn_nba_rosters`. PBP has shot coordinates,
  substitutions, clock, score. Extras for later: `nba_stats_hustle`, `nba_stats_injury_report`.
  Incremental pattern: re-download current-season file daily, merge on play/game id with a lookback window.
  The nba.com notes below are kept for reference only (nba.com CDN returned 403 to plain requests).
- **Superseded sources**
  - `cdn.nba.com` static JSON (schedule, scoreboard, box score, play-by-play): reportedly reachable from
    cloud IPs → daily incremental loads from CI. Undocumented — verify first thing in Phase 1.
  - `stats.nba.com` via `nba_api` for history (players, teams, past seasons). **It blocks cloud/datacenter
    IPs (incl. GitHub Actions)**, so historical backfill runs once from your laptop.
  - Fallback: balldontlie free tier (5 req/min; teams/players/games only) or a public Kaggle NBA dataset
    for backfill.
  - Terms: NBA data is for personal, non-commercial use → **don't commit raw data to the repo**; the repo
    holds code, a small sample fixture set for CI, and attribution.
- **Why it's good AE material:** stat corrections after games (late/revised data → incremental lookback +
  snapshots), postponed/rescheduled games, player trades and team changes (SCD2), multiple grains
  (season → game → possession → play event), and play-by-play parsing that genuinely needs unit tests.
- **Gold marts (draft):** `fct_team_games`, `fct_player_games`, `fct_possessions`, `fct_shots` (with shot
  zones), `fct_lineup_stints`; `dim_players` (SCD2), `dim_teams`, `dim_games`, `dim_seasons`, `dim_date`.
- **Silver highlights:** parsed play events, possession builder, on-court lineup tracker (hardest logic →
  unit-test showcase), reconciled box scores.
- **Metrics (draft):** points per 100 possessions (offensive/defensive rating — ratio), net rating (derived),
  pace, eFG% and TS% (derived), turnover rate, season-to-date points/wins (cumulative), rolling 10-game
  ratings (cumulative window), clutch-time win % (filtered ratio), conversion: offensive rebound → score
  within the same possession.

### Alternates (if NBA ingestion turns out unreliable)
| Topic | Sources | Live | History | Notes |
|---|---|---|---|---|
| US power grid & carbon | EIA-930 API + NOAA + EPA eGRID | daily, revised | ●●○ | public domain, strongest ops story |
| Open-source ecosystem | GH Archive hourly events + PyPI stats | hourly | ●●○ | best conversion/cohort metrics |
| Citi Bike + weather | trip files + live GBFS feed + NOAA | monthly / live | ●●● stations | product-analytics feel |
| Air quality | OpenAQ API + NASA FIRMS fires | hourly | ●●○ | CC BY 4.0, noisy data |
| Earthquakes | USGS real-time feed + FEMA + Census | minutes | ●●● revisions | small volume |
| Tennis | Sackmann CSVs | frozen ~2024 | weekly rankings | CC BY-NC-SA, no live feed |
| Higher education | College Scorecard + IPEDS | annual | ●○○ | weak on ops |

---

## 3. Platform setup ($0)

**Warehouse: DuckDB (dev + CI) + MotherDuck free tier (prod).**
- DuckDB: zero setup for reviewers and CI; MetricFlow has a DuckDB renderer.
- MotherDuck free plan: 10 GB storage, 10 compute-hours/month, no card → persistent prod so Slim CI can
  `--defer` and Recce can diff PR vs prod. NBA data volume is small (a few seasons of play-by-play ≈ low GBs
  as parquet).
- **BigQuery sandbox rejected:** blocks DML (incremental `merge` and snapshots fail) and expires tables after
  60 days; the free tier needs a billing card. ADR documents this; `profiles.yml` keeps a BigQuery/Snowflake
  target stub and SQL uses dbt cross-database macros.

**Orchestration: Airflow, $0.**
- No hosted Airflow is free: Astronomer is a 14-day trial then ~$0.35/hr; AWS MWAA and Cloud Composer are
  paid. (Prefect Cloud has a free hobby tier, but it isn't Airflow.)
- Approach: Airflow 3 + **Astronomer Cosmos** defined in `orchestration/`, run locally with the free Astro
  CLI (Docker). The **scheduled prod run is a GitHub Actions cron that executes the same DAG headless**
  (`airflow dags test <dag> <date>` with a throwaway SQLite metadata DB), so there's one DAG definition,
  real Airflow code, and $0 hosting. ADR explains the trade-off and how it would map to Astro/MWAA.
- DAGs: `nba_daily` (ingest yesterday's games → dbt build via Cosmos → freshness → upload artifacts),
  `nba_backfill` (parameterized by season/date range), `dbt_docs_publish`.

**Tooling (pinned in `pyproject.toml`, `uv`):** dbt-core 1.10+/dbt-duckdb, dbt-metricflow, apache-airflow
+ astronomer-cosmos, SQLFluff (dbt templater), dbt-checkpoint, pre-commit, Recce (OSS), elementary
(optional), nba_api, httpx/tenacity, pytest.

**Repo layout**
```
.github/
  workflows/ ci.yml  prod.yml (cron → Airflow DAG)  fusion-compat.yml  docs.yml
  CODEOWNERS  pull_request_template.md
ingestion/            # extractors → bronze parquet / raw tables (+ pytest, recorded fixtures)
orchestration/        # Airflow DAGs (Cosmos), Astro CLI project
transform/            # dbt project
  models/bronze/<source>/      # 1:1 staging views over raw
  models/silver/<domain>/      # cleaned, conformed, business logic
  models/gold/<domain>/        # facts/dims — contracted, public, MetricFlow input
  models/semantic/             # semantic_models, metrics, saved_queries
  snapshots/ tests/ macros/ seeds/ analyses/ fixtures/
docs/adr/  STYLE_GUIDE.md  METRICS.md (generated)  CONTRIBUTING.md
.devcontainer/  Makefile  pyproject.toml  .sqlfluff  .pre-commit-config.yaml
```

**Data flow:** extract → bronze (raw JSON/parquet with `_loaded_at`, source URL, load id; idempotent per
game/date) → silver → gold → MetricFlow saved queries/exports. Prod artifacts (`manifest.json`,
`run_results.json`) saved each run for Slim CI and observability.

---

## 4. CI/CD design (team-scale)

**Pre-commit:** SQLFluff lint/fix, dbt-checkpoint (descriptions, column docs, tests present, no hard-coded
relations), YAML format, ruff for Python.

**`ci.yml` on every PR**
1. Lint + pre-commit + pytest for ingestion and DAG import test (fast fail).
2. Download latest prod manifest; `dbt build --select state:modified+ --defer --state prod/` into a
   PR-scoped schema (CI uses the checked-in sample fixtures when running on DuckDB).
3. Unit tests run inside `dbt build`; contracts enforced on gold `access: public` models.
4. dbt-project-evaluator (fan-outs, missing PK tests, layer violations e.g. gold → bronze refs).
5. `mf validate-configs` + smoke `mf query` on certified metrics; known-answer metric tests.
6. Recce: lineage + row-count/profile diff vs prod → PR comment.
7. Breaking-change guard: contract change on a public gold model without a new version → fail.
8. Drop the PR schema on close.

**`fusion-compat.yml`:** `dbtf parse/compile` with dbt Core v2, non-blocking, badge in README.

**Repo governance:** branch protection (CI + 1 review), CODEOWNERS by domain, PR template (change,
downstream impact, metric changes), conventional commits, CHANGELOG for public model versions.

---

## 5. Build phases (each ends in merged PRs so history tells the story)

1. **Foundation & source spike** — confirm NBA endpoints from GitHub Actions (else pick alternate), repo
   skeleton, uv/devcontainer, DuckDB profile, one source → bronze, style guide, pre-commit, first `ci.yml`.
2. **Bronze/silver/gold** — all sources, silver logic (play parsing, possessions, lineups), gold
   facts/dims, date spine, incremental/microbatch with lookback for stat corrections, player SCD2 snapshot,
   unit tests, contracts on gold.
3. **Semantic layer** — semantic models, 12–15 metrics across types, saved queries, governance meta,
   generated METRICS.md, MetricFlow checks in CI.
4. **Orchestration & prod** — Airflow + Cosmos DAGs, MotherDuck prod, GitHub Actions cron running the DAG,
   backfill DAG, freshness + failure alerts, artifacts, dbt docs on Pages.
5. **Team-scale CI & governance** — Slim CI with defer, Recce PR comments, project-evaluator, CODEOWNERS,
   access/groups, a real v1→v2 model-version migration, breaking-change guard, ADRs, metric RFC PR.
6. **Stretch** — elementary observability, Elo Python model, Fusion compat green.

---

## 6. Verification
- Fresh clone/Codespace: `make setup && make build` passes all tests on DuckDB with sample fixtures.
- `mf query --saved-query <name>` returns expected values; box-score/team-total reconciliation tests pass.
- Deliberately breaking PR (drop a contracted column, change a metric) → CI fails at the right step and
  Recce comment shows impact; a clean PR builds only `state:modified+`.
- Airflow: `astro dev start` shows the Cosmos task graph; the cron workflow runs `nba_daily` twice in a row
  idempotently; backfill DAG reloads a past date without duplicates; freshness passes; docs site updates.
- MotherDuck usage stays within the free plan.

## Open items at build start
- Final topic (NBA vs. alternate) after the Phase 1 endpoint spike.
- Seasons to backfill (suggest last 3 regular seasons + playoffs).
