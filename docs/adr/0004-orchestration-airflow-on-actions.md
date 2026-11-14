# ADR 0004: Airflow + Cosmos DAGs, scheduled on GitHub Actions, against MotherDuck

- Status: accepted
- Date: 2026-11-13

## Context

Prod needs a daily schedule, retries, alerting, backfills and per-model visibility, at $0.
Airflow is the most common orchestrator in analytics-engineering job posts, but no hosted Airflow
is free: Astronomer is a 14-day trial then about $0.35/hour, and AWS MWAA and Google Cloud Composer
are paid. Prefect Cloud has a free tier but is not Airflow.

## Decision

- **DAGs are real Airflow 3 code** in `orchestration/dags/`, with **Astronomer Cosmos** rendering
  the dbt project as one Airflow task per model (plus seeds, snapshots and tests).
  - Rendered from `manifest.json` (`LoadMode.DBT_MANIFEST`), so parsing the DAG never runs dbt.
  - `TestBehavior.AFTER_EACH`: a model's tests run right after it and a failure stops its
    downstream models. Tests that span several models (relationships to dimensions,
    reconciliation tests) get their own task that waits for all of them.
  - dbt tasks retry once after a minute (dropped connections); failing data tests are not
    retried with long backoff.
- **Airflow lives in its own uv environment** (`orchestration/pyproject.toml`). dbt, MetricFlow
  and ingestion run from the project environment via `dbt_executable_path` and `PATH`, so Airflow's
  dependency pins never constrain dbt's.
- **Schedule and compute come from GitHub Actions** (`.github/workflows/prod.yml`): a daily cron
  runs `airflow dags test nba_daily` on a runner with a throwaway SQLite metadata DB. The DAG code
  is identical to what a hosted Airflow would run; moving to Astronomer or MWAA means deploying
  `orchestration/` and deleting the cron, not rewriting DAGs.
- **Alerts**: every task has an `on_failure_callback` that logs a structured summary and appends it
  to `NBA_ALERTS_FILE`; the workflow opens (or comments on) a `prod-failure` issue with it.
  Airflow sets a run's state from its final tasks, and `source_freshness` runs even after
  failures (`all_done`), so a run with a failed task could still end as success and
  `airflow dags test` exit 0 (seen on 3.3.2). A watcher task downstream of every task
  (`trigger_rule="one_failed"`) fails the run if anything failed, and the workflow also fails if
  the alerts file is non-empty, as a second check.
- **Warehouse**: MotherDuck free plan (`md:nba`). The token is a `prod` environment secret that
  only deploys from `main`, and only the steps that connect to MotherDuck receive it
  ([docs/prod-setup.md](../prod-setup.md)).
  Ingestion creates the database on first run. A local DuckDB file allows one writer, so DAGs run
  one task at a time against a file and four at a time against MotherDuck.
- **Deploys of incremental models**: the prod workflow downloads the last successful run's
  manifest, and the DAG's first dbt-related task drops incremental models that changed since then
  so they are rebuilt (ADR 0003).
- **Freshness** runs last with `trigger_rule="all_done"` and no retries: stale upstream data alerts
  but does not block publishing what we have.

## Not chosen

- Astro CLI / Docker project: the Astro CLI needs Docker; a Dockerfile nobody runs would rot. The
  same DAGs run with `make airflow-ui` (`airflow standalone`) on any machine with Python.
- Running dbt as one `dbt build` task: simpler, but loses per-model retries, timing and lineage in
  the Airflow UI, which is the point of Cosmos.

## Consequences

- No always-on scheduler: there is no Airflow UI for prod runs; run history is the Actions log and
  the `prod-dbt-state` artifact. Locally, `make airflow-ui` gives the full UI.
- Each Cosmos task starts a dbt process (~3 s overhead), so the daily run takes minutes, not
  seconds (191 s end to end in a local prod rehearsal, run serially against a DuckDB file).
  Acceptable for a daily job; `ExecutionMode.WATCHER` or a single build task are the levers if it
  ever matters.
