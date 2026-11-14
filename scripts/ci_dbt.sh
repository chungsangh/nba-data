#!/usr/bin/env bash
# The dbt part of CI, shared by .github/workflows/ci.yml and local runs.
#
#   BASELINE_DIR=path/to/main/state scripts/ci_dbt.sh   # Slim CI against main's baseline
#   scripts/ci_dbt.sh                                   # full build
#
# Slim CI: build only modified models and everything downstream of them, reading unchanged
# parents from main's baseline (--defer). Then `dbt clone` the unchanged models into this PR's
# schemas as views, so the semantic layer checks and the data diff see a complete project.
#
# Breaking-change guard: removing or retyping a column of a contracted model without a new model
# version fails the build. Set ALLOW_BREAKING_CHANGE=true (the approved-breaking-change PR label)
# for a deliberate, reviewed break.
#
# Expects DBT_PROFILES_DIR, DBT_TARGET and NBA_DUCKDB_PATH to be set, like the Makefile does.
set -euo pipefail

cd "$(dirname "$0")/../transform"

if [ "${ALLOW_BREAKING_CHANGE:-false}" = "true" ]; then
    echo "::warning::Breaking contract changes allowed (approved-breaking-change label)."
    guard='{"error": []}'
else
    guard='{"error": ["UnversionedBreakingChange"]}'
fi

if [ -n "${BASELINE_DIR:-}" ] && [ -f "${BASELINE_DIR}/manifest.json" ]; then
    echo "== Slim CI: building state:modified+ against main's baseline"
    uv run dbt build --select state:modified+ --defer --state "$BASELINE_DIR" \
        --warn-error-options "$guard"
    echo "== Cloning unchanged models from the baseline"
    uv run dbt clone --exclude state:modified+ --state "$BASELINE_DIR"
else
    echo "== Full build (no baseline available)"
    uv run dbt build
fi

echo "== Semantic layer: MetricFlow validation and known-answer checks"
uv run mf validate-configs
uv run python ../scripts/check_metrics.py

echo "== Project structure: dbt-project-evaluator (findings fail the build)"
DBT_PROJECT_EVALUATOR=true DBT_PROJECT_EVALUATOR_SEVERITY=error \
    uv run dbt build --select package:dbt_project_evaluator dbt_project_evaluator_exceptions
