# Contributing

## Workflow

1. Branch from `main`, run `make setup` once (installs the pre-commit hooks).
2. Make the change; `make build` and `make metrics-check` locally.
3. Open a PR using the template. CI builds your change into its own `ci_pr_<n>_*` schemas, so it
   never touches anyone else's data.
4. One approving review, green CI, then squash-merge.

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
