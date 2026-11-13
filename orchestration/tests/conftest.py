import sys
from pathlib import Path

# Airflow puts the DAGs folder on sys.path in its own processes; do the same for pytest so the
# DAGs can import their shared nba_config module.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "dags"))
