import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "metrics_catalog", Path(__file__).resolve().parents[1] / "metrics_catalog.py"
)
catalog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalog)


def metric(name, kind="ratio", meta=None, measure=None, numerator=None, denominator=None):
    params = {"measure": {"name": measure} if measure else None, "metrics": []}
    if numerator:
        params["numerator"] = {"name": numerator}
        params["denominator"] = {"name": denominator}
    return {"name": name, "type": kind, "type_params": params, "config": {"meta": meta or {}}}


def test_building_block_without_meta_is_allowed():
    block = metric("team_points", kind="simple", measure="team_points")
    assert catalog.governance_errors([block]) == []


def test_published_metric_needs_owner_and_valid_tier():
    errors = catalog.governance_errors(
        [metric("pace", kind="simple", measure="x", meta={"tier": "gold"})]
    )
    assert "pace: missing meta.owner" in errors
    assert any("meta.tier must be one of" in e for e in errors)


def test_certified_metric_cannot_depend_on_experimental():
    experimental = metric(
        "pace", kind="simple", measure="x", meta={"owner": "a", "tier": "experimental"}
    )
    certified = metric(
        "pace_ratio", numerator="pace", denominator="pace", meta={"owner": "a", "tier": "certified"}
    )
    assert catalog.governance_errors([experimental, certified]) == [
        "pace_ratio: certified metric depends on experimental pace",
        "pace_ratio: certified metric depends on experimental pace",
    ]


def test_filter_is_rendered_without_jinja():
    ref = {
        "name": "shots_made",
        "filter": {
            "where_filters": [{"where_sql_template": "{{ Dimension('shot__shot_zone') }} = 'x'"}]
        },
    }
    assert catalog._input(ref) == "`shots_made` where shot__shot_zone = 'x'"
