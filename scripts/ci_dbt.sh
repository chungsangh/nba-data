#!/usr/bin/env bash
# The dbt parts of CI, shared by .github/workflows/ci.yml and `make ci`.
#
#   scripts/ci_dbt.sh build       dbt build + guard + clone + semantic layer checks
#   scripts/ci_dbt.sh structure   dbt-project-evaluator (needs no data)
#   scripts/ci_dbt.sh             both (local use)
#
# build, with BASELINE_DIR pointing at main's state (manifest.json): Slim CI. Build only modified
# models and everything downstream, reading unchanged parents from main's baseline (--defer), then
# `dbt clone` the unchanged models into this PR's schemas as views, so the semantic layer checks
# and the data diff see a complete project. Without BASELINE_DIR: full build.
#
# Breaking-change guard (Slim CI only): removing or retyping a column of a contracted model
# without a new model version fails the build. ALLOW_BREAKING_CHANGE=true (the
# approved-breaking-change PR label) allows a deliberate, reviewed break.
#
# Expects DBT_PROFILES_DIR, DBT_TARGET and NBA_DUCKDB_PATH to be set, like the Makefile does.
set -euo pipefail

mode="${1:-all}"
cd "$(dirname "$0")/../transform"

run_build() {
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
}

run_structure() {
    echo "== Project structure: dbt-project-evaluator (findings fail the build)"
    DBT_PROJECT_EVALUATOR=true DBT_PROJECT_EVALUATOR_SEVERITY=error \
        uv run dbt build --select package:dbt_project_evaluator dbt_project_evaluator_exceptions
}

case "$mode" in
    build) run_build ;;
    structure) run_structure ;;
    all) run_build && run_structure ;;
    *) echo "usage: $0 [build|structure|all]" >&2; exit 2 ;;
esac
