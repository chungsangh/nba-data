# Contributing

## Workflow

1. Branch from `main`, run `make setup` once (installs the pre-commit hooks).
2. Make the change; `make build` and `make metrics-check` locally.
3. Open a PR using the template. CI builds your change into its own `ci_pr_<n>_*` schemas, so it
   never touches anyone else's data.
4. One approving review, green CI, then squash-merge.

What CI does on your PR, as four checks:

- **Lint & unit tests**: pre-commit hooks, pytest, Airflow DAG tests.
- **dbt build**: builds only what you changed plus everything downstream (Slim CI against `main`'s
  last build), runs every test, enforces contracts, validates the semantic layer.
- **Project structure**: dbt-project-evaluator.
- **Data diff (advisory)**: a Recce comment showing what your change did to the data. It never
  blocks a merge, but read it.

`make ci` runs the dbt checks locally.

## Changing a gold model's columns

Gold models are public and contracted. Adding a column is fine. Removing, renaming or retyping
one breaks consumers, so:

1. Add a new model version (`versions:` in the model's YAML) with the new shape and make it
   `latest_version`.
2. Keep the old version on the original relation name (`config: alias:`) with a
   `deprecation_date`, so existing queries keep working.
3. Move internal refs and semantic models to the new version.
4. Remove the old version after its deprecation date.

CI fails a contract break without a new version. If a break is truly intended, a reviewer adds the
`approved-breaking-change` label (see ADR 0005).

## Ownership

Models belong to a dbt group (`platform` or `game_analytics`, see
`transform/models/_groups.yml`). Silver models are private to their group: to use another
group's silver model, ask its owner to make it `protected` or expose what you need in gold.

See [STYLE_GUIDE.md](STYLE_GUIDE.md) for layer rules, naming and testing standards, and
[docs/adr/](docs/adr/) for why things are the way they are.

## Changing metrics

Metrics live in `transform/models/semantic/`. [METRICS.md](METRICS.md) is generated from them.

| Change | What's required |
|---|---|
| New metric | `label`, `description`, `meta.owner`, `meta.tier`. Start as `experimental` unless it is a textbook definition with a known-answer test. |
| Promote to `certified` | A known-answer check in `scripts/check_metrics.py` (MetricFlow vs independent SQL) and owner approval. |
| Change a certified metric's definition | Owner approval in the PR, and a note in the PR description of how values move (run the saved query before and after). |
| Rename or remove a certified metric | Add the replacement first, mark the old one deprecated in its description for one release, then remove. |

Rules enforced automatically (pre-commit and CI):

- Every published metric has an owner and a tier of `certified` or `experimental`.
- A certified metric may not depend on an experimental one.
- `METRICS.md` matches the YAML (`make metrics-catalog` regenerates it).
- `mf validate-configs` passes against the warehouse, and certified saved queries match
  independent SQL (`scripts/check_metrics.py`).

Building-block metrics (`create_metric: true` on a measure) carry no owner or tier; they exist to
feed published metrics and are listed separately in the catalog.
