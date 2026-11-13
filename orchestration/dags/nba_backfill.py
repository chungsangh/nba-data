"""Manual backfill: reload whole seasons and rebuild.

Trigger with params, e.g. {"seasons": [2025, 2026], "full_refresh": true}.

Ingestion replaces each requested season. The incremental gold models only reprocess the last few
days on a normal run, so after reloading old seasons they need `full_refresh` (the default here).
Snapshots are not affected by --full-refresh, so player history is kept.
"""

from __future__ import annotations

from datetime import datetime, timedelta

from airflow.providers.standard.operators.bash import BashOperator
from airflow.sdk import DAG, Param

from nba_config import (
    DBT_PROJECT_DIR,
    DEFAULT_ARGS,
    MAX_ACTIVE_TASKS,
    REPO_ROOT,
    TASK_ENV,
    current_season,
)

with DAG(
    dag_id="nba_backfill",
    description="Reload whole seasons and rebuild the warehouse.",
    schedule=None,
    start_date=datetime(2026, 11, 1),
    catchup=False,
    max_active_runs=1,
    max_active_tasks=MAX_ACTIVE_TASKS,
    dagrun_timeout=timedelta(hours=4),
    default_args=DEFAULT_ARGS,
    tags=["nba", "backfill"],
    doc_md=__doc__,
    params={
        "seasons": Param(
            [current_season() - 1, current_season()],
            type="array",
            items={"type": "integer", "minimum": 2002},
            description="ESPN season labels to reload (2026 = the 2025-26 season).",
        ),
        "full_refresh": Param(
            True, type="boolean", description="Rebuild incremental models from scratch."
        ),
    },
) as dag:
    ingest = BashOperator(
        task_id="ingest_seasons",
        bash_command=(
            f"cd {REPO_ROOT} && nba-ingest --seasons {{{{ params.seasons | join(' ') }}}}"
        ),
        env=TASK_ENV,
        append_env=True,
    )

    build = BashOperator(
        task_id="dbt_build",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && dbt deps --quiet && dbt build "
            "{{ '--full-refresh' if params.full_refresh else '' }}"
        ),
        env=TASK_ENV,
        append_env=True,
        execution_timeout=timedelta(hours=3),
    )

    semantic_layer_checks = BashOperator(
        task_id="semantic_layer_checks",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && mf validate-configs && "
            f"cd {REPO_ROOT} && python scripts/check_metrics.py"
        ),
        env=TASK_ENV,
        append_env=True,
    )

    ingest >> build >> semantic_layer_checks
