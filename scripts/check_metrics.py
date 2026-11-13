"""Known-answer tests for the semantic layer.

Runs certified saved queries through MetricFlow and recomputes the same numbers with
independently written SQL straight from the gold tables. Any difference means a metric
definition, a semantic model join, or a gold model changed meaning.

    uv run python scripts/check_metrics.py

Needs a built warehouse (`make build`) and the DBT_PROFILES_DIR / NBA_DUCKDB_PATH variables
that the Makefile sets.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
TOLERANCE = 1e-6

# Independent definitions, written from the basketball formulas rather than the YAML.
EXPECTED_TEAM_RATINGS = """
select
    t.team_abbreviation as team__team_abbreviation,
    f.season as team_game__season,
    f.season_type as team_game__season_type,
    count(*) as games_played,
    avg(case when f.is_win then 1.0 else 0.0 end) as win_pct,
    100.0 * sum(f.points) filter (where f.possessions is not null)
        / sum(f.possessions) as offensive_rating,
    100.0 * sum(f.opponent_points) filter (where f.opponent_possessions is not null)
        / sum(f.opponent_possessions) as defensive_rating,
    (sum(f.field_goals_made) + 0.5 * sum(f.three_pointers_made))
        / sum(f.field_goals_attempted) as effective_fg_pct,
    sum(f.points) / (2 * (sum(f.field_goals_attempted) + 0.44 * sum(f.free_throws_attempted)))
        as true_shooting_pct
from {gold}.fct_team_games as f
join {gold}.dim_teams as t using (team_id)
where f.counts_toward_record
group by all
"""

EXPECTED_SHOT_PROFILE = """
select
    shot_zone as shot__shot_zone,
    season as shot__season,
    count(*) as shot_attempts,
    avg(case when is_made then 1.0 else 0.0 end) as shot_fg_pct,
    avg(points) as points_per_shot
from {gold}.fct_shots
group by all
"""

CHECKS = [
    (
        "team_ratings_by_season",
        EXPECTED_TEAM_RATINGS,
        ["team__team_abbreviation", "team_game__season", "team_game__season_type"],
    ),
    ("league_shot_profile", EXPECTED_SHOT_PROFILE, ["shot__shot_zone", "shot__season"]),
]


def gold_schema() -> str:
    target = os.environ.get("DBT_TARGET", "dev")
    if target == "prod":
        return "gold"
    if target == "ci":
        return f"ci_{os.environ.get('CI_SCHEMA_SUFFIX', 'local').lower()}_gold"
    return f"dev_{os.environ.get('USER', 'local').lower()}_gold"


def run_saved_query(name: str, out: Path) -> None:
    subprocess.run(
        ["mf", "query", "--saved-query", name, "--csv", str(out), "--quiet"],
        cwd=ROOT / "transform",
        check=True,
    )


def compare(con, name: str, expected_sql: str, keys: list[str], csv: Path) -> list[str]:
    con.execute(f"create or replace temp table actual as select * from read_csv_auto('{csv}')")
    con.execute(
        f"create or replace temp table expected as {expected_sql.format(gold=gold_schema())}"
    )
    columns = [d[0] for d in con.execute("select * from expected limit 0").description]
    metrics = [c for c in columns if c not in keys]
    join = " and ".join(f"a.{k} is not distinct from e.{k}" for k in keys)
    problems = []
    for metric in metrics:
        key_cols = ", ".join(
            f"coalesce(cast(e.{k} as varchar), cast(a.{k} as varchar))" for k in keys
        )
        rows = con.execute(
            f"""
            select {key_cols},
                   a.{metric}, e.{metric}
            from actual a full outer join expected e on {join}
            where a.{metric} is null <> e.{metric} is null
               or abs(a.{metric} - e.{metric}) > {TOLERANCE}
            limit 5
            """
        ).fetchall()
        problems += [
            f"{name}.{metric} {row[:-2]}: metricflow={row[-2]} sql={row[-1]}" for row in rows
        ]
    n = con.execute("select count(*) from expected").fetchall()[0][0]
    print(f"{name}: compared {len(metrics)} metrics across {n} rows")
    return problems


def main() -> int:
    problems: list[str] = []
    with tempfile.TemporaryDirectory() as tmp:
        for name, _, _ in CHECKS:
            run_saved_query(name, Path(tmp) / f"{name}.csv")
        # MetricFlow has released its connection; open the warehouse read-only for the SQL side.
        con = duckdb.connect(os.environ["NBA_DUCKDB_PATH"], read_only=True)
        for name, sql, keys in CHECKS:
            problems += compare(con, name, sql, keys, Path(tmp) / f"{name}.csv")
    for problem in problems:
        print(f"MISMATCH {problem}", file=sys.stderr)
    print(
        "OK: MetricFlow matches independent SQL" if not problems else f"{len(problems)} mismatches"
    )
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
