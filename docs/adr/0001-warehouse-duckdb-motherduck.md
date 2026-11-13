# ADR 0001: DuckDB for dev/CI, MotherDuck for prod

- Status: accepted
- Date: 2026-11-13

## Context

The project must cost $0, be runnable by anyone who clones it, and still exercise the patterns a
production warehouse needs: incremental `merge`, snapshots, per-PR schemas, and a persistent prod
environment that CI can defer to.

## Options considered

| Option | For | Against |
|---|---|---|
| **DuckDB + MotherDuck free plan** | Zero setup locally and in CI; same engine in every environment; free plan has 10 GB storage and 10 compute hours/month, no card | Smaller ecosystem than Snowflake/BigQuery |
| BigQuery sandbox | Real cloud warehouse, free | Blocks DML, so incremental `merge` and snapshots fail; every table expires after 60 days; the paid free tier needs a billing card |
| Snowflake trial | Most common in job posts | Trial ends; reviewers can't run it |

## Decision

DuckDB locally and in CI; MotherDuck (`md:nba`) as prod. SQL stays portable through dbt
cross-database macros, and `profiles.yml` is the only place that knows the engine.

## Consequences

- A reviewer runs the whole project with `make setup ingest build`, no accounts needed.
- Moving to Snowflake or BigQuery means a new profile target and checking adapter-specific
  functions (`regexp_replace` flags, `timezone()`), not a rewrite.
