"""DAG integrity tests: every DAG imports, has an owner and retries, and the daily DAG renders
one Cosmos task per dbt model with its tests attached."""

from pathlib import Path

import pytest
from airflow.models import DagBag

DAGS_DIR = Path(__file__).resolve().parents[1] / "dags"


@pytest.fixture(scope="session")
def dagbag():
    return DagBag(dag_folder=str(DAGS_DIR))


def test_no_import_errors(dagbag):
    assert dagbag.import_errors == {}


def test_expected_dags(dagbag):
    assert set(dagbag.dag_ids) == {"nba_daily", "nba_backfill"}


@pytest.mark.parametrize("dag_id", ["nba_daily", "nba_backfill"])
def test_every_task_has_owner_retries_and_alerting(dagbag, dag_id):
    for task in dagbag.get_dag(dag_id).tasks:
        assert task.owner == "analytics_engineering", task.task_id
        assert task.on_failure_callback, task.task_id
        if task.task_id not in {"source_freshness", "fail_run_if_any_task_failed"}:
            assert task.retries >= 1, task.task_id


def test_daily_renders_dbt_models_with_tests(dagbag):
    dag = dagbag.get_dag("nba_daily")
    task_ids = set(dag.task_ids)
    for model in ["stg_espn__plays", "int_plays_sequenced", "fct_team_games", "fct_shots"]:
        assert f"dbt.{model}.run" in task_ids
        assert f"dbt.{model}.test" in task_ids
    assert "dbt.snap_players.snapshot" in task_ids
    assert "dbt.play_type_categories.seed" in task_ids


def test_daily_order(dagbag):
    dag = dagbag.get_dag("nba_daily")
    ingest = dag.get_task("ingest_current_season")
    reset = dag.get_task("reset_changed_incremental_models")
    freshness = dag.get_task("source_freshness")
    watcher = {"fail_run_if_any_task_failed"}
    # changed incremental models are dropped after ingestion and before any dbt task runs
    assert ingest.downstream_task_ids - watcher == {"reset_changed_incremental_models"}
    after_reset = reset.downstream_task_ids - watcher
    assert after_reset and all(t.startswith("dbt.") for t in after_reset)
    assert freshness.trigger_rule == "all_done"


def test_daily_run_fails_when_any_task_fails(dagbag):
    dag = dagbag.get_dag("nba_daily")
    watcher = dag.get_task("fail_run_if_any_task_failed")
    assert watcher.trigger_rule == "one_failed"
    assert set(watcher.upstream_task_ids) == set(dag.task_ids) - {watcher.task_id}
