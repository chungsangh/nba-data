# ADR 0005: Slim CI against main's baseline, breaking-change guard, ownership

- Status: accepted
- Date: 2026-11-13

## Context

With many contributors, CI has to stay fast as the project grows, show reviewers what a change does
to the data (not just the SQL diff), and stop accidental breaks of the gold interface that
consumers and MetricFlow depend on. Ownership has to be enforced, not just written down.

The textbook Slim CI (`--defer` to prod) would mean PR builds reading MotherDuck, which puts a
warehouse token in front of every branch, and ADR 0004 keeps that token to `main`-only prod runs.

## Decision

### Slim CI against main's own baseline

- Every CI run on `main` saves a **baseline** artifact: the built DuckDB file (about 23 MB for the
  current season) plus `manifest.json` and `catalog.json`.
- A PR downloads it, builds only `state:modified+` with `--defer --state baseline` (unchanged
  parents are read from the baseline's `ci_main_*` schemas in the same file), then runs
  `dbt clone` to put the unchanged models into the PR's schemas as views. MetricFlow validation,
  the known-answer checks and the data diff then see a complete project.
- PRs that change ingestion code or Python dependencies fall back to a full build, because the
  baseline's data would not reflect them.
- One script, `scripts/ci_dbt.sh`, holds this logic for both CI and `make ci`.

Measured locally: a PR changing one model built 10 nodes instead of 137 and cloned the rest.

### Breaking-change guard

dbt compares contracts against the baseline. Breaking a **versioned** model's contract is an
error; breaking an **unversioned** one is only a warning. CI turns that warning
(`UnversionedBreakingChange`) into an error. A deliberate break needs a reviewer to add the
`approved-breaking-change` label, which reruns CI without the escalation. The expected path is a
new model version instead (see `dim_games` v1 → v2).

### Data diff on every PR

Recce compares the PR's build with the baseline (row counts and schema of changed models, plus
the lineage of what changed) and posts a summary comment, updated on each push. The full state is
uploaded as an artifact for `recce server --review`.

### Project structure checks

dbt-project-evaluator runs in CI with severity `error`. Approved exceptions live in
`seeds/dbt_project_evaluator_exceptions.csv`, each with a reason. It is disabled in normal builds
(`DBT_PROJECT_EVALUATOR`), so prod and Cosmos never see its models.

### Ownership

- dbt **groups**: `platform` (ingestion, bronze, league dimensions) and `game_analytics`
  (play-by-play logic, game facts). Silver is `private` to its group; the shared game
  classification is explicitly `protected`; gold is `public` with enforced contracts.
- `.github/CODEOWNERS` routes reviews by the same boundaries; metric `meta.owner` matches.

### Model versions

`dim_games` v2 replaces two mutually exclusive flags with one `game_type` column. v1 keeps the
original relation name (`gold.dim_games`) and a deprecation date of 2027-01-31; `ref('dim_games')`
resolves to v2.

## Consequences

- The baseline is main's CI data (current season, built minutes after merge), not prod. Diffs
  compare code changes on identical inputs, which is what review needs; prod-vs-PR data drift is
  not shown.
- Until main has produced a baseline (first merge after this change), PRs run full builds.
- `dim_games_v1` is removed after its deprecation date, in a PR that will itself need the
  `approved-breaking-change` label.
