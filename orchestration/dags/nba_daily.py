"""Daily production run.

    ingest current season ─► reset changed incremental models
        ─► dbt (Cosmos: one task per model, tests right after each model)
        ─► semantic layer checks ─► source freshness (alerts, never blocks)

The publisher refreshes around 07:30 ET (12:30 UTC); the run starts at 14:00 UTC. Ingestion
replaces the whole current season, and the incremental models reprocess the last 3 days, so
stat corrections land without a backfill. When a deploy changed an incremental model (or anything
upstream of it) since the last prod run, that model is dropped first and rebuilt from scratch, so
a column change can't fail the run and old history isn't left computed with old logic.
"""

from __future__ import annotations

from datetime import datetime, timedelta

from airflow.exceptions import AirflowException
from airflow.providers.standard.operators.bash import BashOperator
from airflow.sdk import DAG, task
from cosmos import (
    DbtTaskGroup,
    ExecutionConfig,
    ProfileConfig,
    ProjectConfig,
    RenderConfig,
)
from cosmos.constants import LoadMode, TestBehavior

from nba_config import (
    DBT_EXECUTABLE,
    DBT_MANIFEST,
    DBT_PROJECT_DIR,
    DBT_TARGET,
    DEFAULT_ARGS,
    MAX_ACTIVE_TASKS,
    REPO_ROOT,
    TASK_ENV,
)

with DAG(
    dag_id="nba_daily",
    description="Ingest the current season, build and test every dbt model, check metrics.",
    schedule="0 14 * * *",
    start_date=datetime(2026, 11, 1),
    catchup=False,
    max_active_runs=1,
    max_active_tasks=MAX_ACTIVE_TASKS,
    dagrun_timeout=timedelta(hours=2),
    default_args=DEFAULT_ARGS,
    tags=["nba", "prod", "dbt"],
    doc_md=__doc__,
) as dag:
    ingest = BashOperator(
        task_id="ingest_current_season",
        doc_md="Replace the current season of every ESPN dataset in the raw schema.",
        bash_command=f"cd {REPO_ROOT} && nba-ingest",
        env=TASK_ENV,
        append_env=True,
    )

    reset_changed_incrementals = BashOperator(
        task_id="reset_changed_incremental_models",
        doc_md=(
            "Compare the code with the last prod run's manifest (NBA_PROD_STATE_DIR) and drop "
            "incremental models that changed or sit downstream of a change, so dbt rebuilds them."
        ),
        # Trailing space: Airflow treats a bash_command ending in ".sh" as a template file path.
        bash_command=f"cd {REPO_ROOT} && scripts/reset_changed_incrementals.sh ",
        env={**TASK_ENV, "DBT_CMD": "dbt"},
        append_env=True,
    )

    dbt = DbtTaskGroup(
        group_id="dbt",
        project_config=ProjectConfig(
            dbt_project_path=DBT_PROJECT_DIR,
            manifest_path=DBT_MANIFEST,
            project_name="nba",
        ),
        profile_config=ProfileConfig(
            profile_name="nba",
            target_name=DBT_TARGET,
            profiles_yml_filepath=DBT_PROJECT_DIR / "profiles.yml",
        ),
        execution_config=ExecutionConfig(dbt_executable_path=str(DBT_EXECUTABLE)),
        render_config=RenderConfig(
            # Render from a manifest built by `dbt parse` instead of running `dbt ls` every time
            # the scheduler parses this file.
            load_method=LoadMode.DBT_MANIFEST,
            # A model's tests (data and unit) run right after it, so a failure stops its
            # downstream models instead of publishing bad data.
            test_behavior=TestBehavior.AFTER_EACH,
            # Tests that span models (e.g. relationships to a dimension) get their own task that
            # waits for every model they reference, instead of running with the first parent.
            should_detach_multiple_parents_tests=True,
        ),
        operator_args={
            # packages are installed once before the run (`dbt deps`), not in every task
            "install_deps": False,
            "env": TASK_ENV,
            "append_env": True,
            # One quick retry covers a dropped warehouse connection; a failing data test
            # will fail again, so don't spend 15 minutes of backoff proving it.
            "retries": min(1, DEFAULT_ARGS["retries"]),
            "retry_delay": timedelta(minutes=1),
            "retry_exponential_backoff": False,
        },
    )

    semantic_layer_checks = BashOperator(
        task_id="semantic_layer_checks",
        doc_md="MetricFlow validation against the warehouse, then known-answer metric tests.",
        bash_command=(
            f"cd {DBT_PROJECT_DIR} && mf validate-configs && "
            f"cd {REPO_ROOT} && python scripts/check_metrics.py"
        ),
        env=TASK_ENV,
        append_env=True,
    )

    source_freshness = BashOperator(
        task_id="source_freshness",
        doc_md=(
            "Stale upstream data should page someone, not stop today's build, so this runs last "
            "and regardless of upstream success."
        ),
        bash_command=f"cd {DBT_PROJECT_DIR} && dbt source freshness",
        env=TASK_ENV,
        append_env=True,
        trigger_rule="all_done",
        retries=0,
    )

    ingest >> reset_changed_incrementals >> dbt >> semantic_layer_checks >> source_freshness

    # Airflow sets a run's state from its final tasks. source_freshness runs even after failures
    # (all_done) and would mark a broken run as successful, so this watcher, downstream of every
    # task, fails the run if anything failed.
    @task(trigger_rule="one_failed", retries=0)
    def fail_run_if_any_task_failed():
        raise AirflowException("A task in this run failed; see the failed task's logs.")

    watcher = fail_run_if_any_task_failed()
    for upstream_task in dag.tasks:
        if upstream_task is not watcher.operator:
            upstream_task >> watcher
