# ADR 0003: Incremental gold facts with lookback, and snapshot-based player history

- Status: accepted
- Date: 2026-11-13

## Context

ESPN corrects stats after games (scorer changes, overturned baskets), and the publisher re-issues
the whole season file each morning. Ingestion already replaces a season per load (ADR 0002), so
raw data is always current. The question is how gold tables pick up corrections without
rebuilding everything on every run, and how to keep player history (trades) that box scores alone
don't timestamp.

## Decision

Two incremental patterns, used where each fits:

| Model | Strategy | Why |
|---|---|---|
| `fct_shots` | `microbatch`, one batch per tip-off day, `lookback=3` | Large, append-mostly, naturally partitioned by time. Batches are independently retryable and any date range can be backfilled with `--event-time-start/--event-time-end`. |
| `fct_possessions` | `delete+insert` on `possession_id`, reprocessing games from the last `possession_lookback_days` (3) | Shows the classic hand-written pattern; the filter lives in the model so reviewers see exactly what is reprocessed. |
| Other gold models | `table` | Small (≤ 40k rows); a full rebuild is cheaper than incremental complexity. |

Both incremental models set `on_schema_change: fail`: with enforced contracts, a column change must
come with a deliberate `--full-refresh` (and, for public models, a new model version).

Player history uses a `check` snapshot (`snap_players`) on team, jersey, position and name over
`int_players_latest`. `dim_players` exposes it as type 2 (`valid_from`, `valid_to`, `is_current`).

### Deploying changes to incremental models

An incremental run only processes new and lookback data, so after a code change it either fails
(columns changed: "source and target schemas are out of sync") or keeps old history computed with
the old logic. CI can't catch this: PR builds create the model from scratch.

Each prod run therefore starts by comparing the code with the last successful prod run's manifest
(the `prod-dbt-state` artifact) and dropping every incremental model in
`state:modified+,config.materialized:incremental`. dbt then rebuilds those from scratch, with
today's upstream data, in the normal run (`scripts/reset_changed_incrementals.sh`, task
`reset_changed_incremental_models`). At this project's size a rebuild takes seconds; a large
warehouse would narrow the selection to contract changes and backfill logic changes deliberately.

## Verification

- Incremental re-run and `--full-refresh` produce identical row counts and point totals for both
  facts (checked 2026-11-13: 298,641 possessions / 342,485 points; 266,603 shots / 288,070 points).
- Changing one player's team in dev and re-running the snapshot closed the old version and
  opened a new one.

## Consequences

- Upstream stat corrections older than the lookback window need a targeted backfill or full
  refresh. Code changes don't: the next prod run rebuilds affected incremental models.
- Between the drop and the rebuild (a minute or two of the prod run) the dropped table is missing.
- The snapshot only records changes from the first prod run onward. Past trades can be derived
  from box scores (team per game) if needed later.
- The first microbatch run processes one batch per day since `date_spine_start` (~30 s on DuckDB).
