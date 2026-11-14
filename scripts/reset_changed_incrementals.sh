#!/usr/bin/env bash
# Before a prod run: drop incremental models whose definition changed since the last prod run,
# so the run rebuilds them from scratch instead of appending to a table built by old code.
#
#   NBA_PROD_STATE_DIR=path/to/last/prod/manifest scripts/reset_changed_incrementals.sh
#
# Why: an incremental run only processes new (and lookback) data. After a change it either fails
# (columns changed: "source and target schemas are out of sync") or silently keeps history
# computed with the old logic. Selection is `state:modified+` intersected with incremental models:
# the model itself changed, or something upstream of it did. Fine at this project's size (a full
# rebuild takes seconds); a large warehouse would narrow this and backfill deliberately.
#
# No previous state (first run, or the artifact expired): does nothing.
# Expects DBT_PROFILES_DIR, DBT_TARGET and NBA_DUCKDB_PATH, like the Makefile sets.
# DBT_CMD overrides how dbt is invoked (the Airflow task uses the project's dbt on PATH).
set -euo pipefail

read -r -a dbt <<< "${DBT_CMD:-uv run dbt}"

cd "$(dirname "$0")/../transform"

state_dir="${NBA_PROD_STATE_DIR:-}"
if [ -z "$state_dir" ] || [ ! -f "$state_dir/manifest.json" ]; then
    echo "No previous prod state: nothing to reset."
    exit 0
fi

models=$("${dbt[@]}" ls --quiet --resource-type model --output name \
    --select "state:modified+,config.materialized:incremental" --state "$state_dir")

if [ -z "$models" ]; then
    echo "No incremental model changed since the last prod run."
    exit 0
fi

names=$(echo "$models" | paste -sd, -)
echo "Incremental models changed since the last prod run: $names"
"${dbt[@]}" run-operation drop_models --args "{model_names: [$names]}"
