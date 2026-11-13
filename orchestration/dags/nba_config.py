"""Settings shared by the nba DAGs.

Airflow runs in its own environment (orchestration/.venv). dbt, MetricFlow and the ingestion CLI
run from the project environment (<repo>/.venv), so the two never share dependencies. Everything
environment-specific comes from environment variables:

    NBA_REPO_ROOT        repo checkout (default: two levels above this file)
    DBT_TARGET           dev | ci | prod (default: dev)
    NBA_DUCKDB_PATH      DuckDB file for dev/ci, or md:<db> for MotherDuck
    MOTHERDUCK_TOKEN     required when the warehouse is MotherDuck
    NBA_ALERTS_FILE      optional: failure summaries are appended here (CI turns them into issues)
"""

from __future__ import annotations

import json
import logging
import os
from datetime import UTC, datetime, timedelta
from pathlib import Path

REPO_ROOT = Path(os.environ.get("NBA_REPO_ROOT", Path(__file__).resolve().parents[2]))
DBT_PROJECT_DIR = REPO_ROOT / "transform"
PROJECT_BIN = REPO_ROOT / ".venv" / "bin"
DBT_EXECUTABLE = PROJECT_BIN / "dbt"
DBT_TARGET = os.environ.get("DBT_TARGET", "dev")
DBT_MANIFEST = Path(
    os.environ.get("NBA_DBT_MANIFEST", DBT_PROJECT_DIR / "target" / "manifest.json")
)
_default_warehouse = "md:nba" if DBT_TARGET == "prod" else str(REPO_ROOT / "data" / "nba.duckdb")
WAREHOUSE = os.environ.get("NBA_DUCKDB_PATH", _default_warehouse)

# A local DuckDB file allows one writer at a time; MotherDuck handles concurrent connections.
IS_LOCAL_DUCKDB = not WAREHOUSE.startswith("md:")
MAX_ACTIVE_TASKS = 1 if IS_LOCAL_DUCKDB else 4

# Environment for every task that shells out to the project tools.
TASK_ENV = {
    "PATH": f"{PROJECT_BIN}:{os.environ.get('PATH', '/usr/bin:/bin')}",
    "DBT_PROFILES_DIR": str(DBT_PROJECT_DIR),
    "DBT_TARGET": DBT_TARGET,
    "NBA_DUCKDB_PATH": WAREHOUSE,
}

log = logging.getLogger(__name__)


def alert_on_failure(context) -> None:
    """Log a structured failure and, if NBA_ALERTS_FILE is set, append it for the CI alert step."""
    ti = context["task_instance"]
    summary = {
        "dag_id": ti.dag_id,
        "task_id": ti.task_id,
        "run_id": context.get("run_id"),
        "try_number": ti.try_number,
        "failed_at": datetime.now(UTC).isoformat(),
        "error": str(context.get("exception"))[:2000],
    }
    log.error("Task failed: %s", json.dumps(summary))
    alerts_file = os.environ.get("NBA_ALERTS_FILE")
    if alerts_file:
        with open(alerts_file, "a") as f:
            f.write(json.dumps(summary) + "\n")


DEFAULT_ARGS = {
    "owner": "analytics_engineering",
    "retries": int(os.environ.get("NBA_TASK_RETRIES", 2)),
    "retry_delay": timedelta(minutes=5),
    "retry_exponential_backoff": True,
    "on_failure_callback": alert_on_failure,
}


def current_season(today: datetime | None = None) -> int:
    """ESPN season label: the season starting in October is labelled by its end year."""
    today = today or datetime.now(UTC)
    return today.year + 1 if today.month >= 8 else today.year
