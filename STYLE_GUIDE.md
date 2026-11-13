# Style guide

Rules here are enforced by tooling wherever possible (SQLFluff, dbt-checkpoint, dbt-project-evaluator
in CI). When a rule is only a convention, reviewers enforce it.

## Layers

| Layer | Folder | Prefix | Materialization | Access | What belongs here |
|---|---|---|---|---|---|
| **Bronze** | `models/bronze/<source>/` | `stg_<source>__<entity>` | view | protected | 1:1 with a raw table. Rename, cast, normalize units/time zones, null out sentinels. **No joins, no business logic.** |
| **Silver** | `models/silver/<domain>/` | `int_<entity>_<verb>` | table | protected | Joins, dedup, ordering fixes, business rules (possessions, lineups). Reusable building blocks; not queried by consumers. |
| **Gold** | `models/gold/<domain>/` | `fct_` / `dim_` | table / incremental | public | Kimball facts and dimensions. Contracts enforced. The only layer MetricFlow and consumers read. |
| Semantic | `models/semantic/` | — | — | — | Semantic models, metrics, saved queries on top of gold. |

Rules of flow: bronze reads only `source()`. Silver reads bronze or silver. Gold reads silver (or
bronze for trivial dims). Nothing reads "up" a layer.

## Naming

- snake_case everywhere. Plural table names (`fct_team_games`), singular entity in the grain.
- Primary key: `<entity>_id`. Foreign keys keep the referenced column's name.
- Booleans: `is_` / `has_`. Timestamps: `<event>_at_utc`. Dates: `<event>_date`.
- Units in the name when ambiguous: `period_seconds_remaining`, `shot_distance_ft`.
- Upstream codes become labels in bronze (`season_type_id` keeps the code, `season_type` the label).

## SQL

- Lowercase keywords and functions, trailing commas, 4-space indents, max 100 characters.
- CTEs, not subqueries. First CTEs import (`select * from {{ ref() }}`), last CTE is `final` or
  the single transformation, and the model ends with `select * from <last cte>`.
- Explicit column lists in silver/gold; `select *` only in import CTEs.
- Group columns by meaning with comments (keys, attributes, measures, timestamps, lineage).

## Testing

- Every model: primary key `unique` + `not_null`.
- Every non-trivial expression (parsing, CASE logic, window functions): a **unit test**.
- Known upstream issues: a singular test with `severity: warn` and tag `known_issue`, with a comment
  naming which model resolves it.
- Gold: `contract: {enforced: true}` plus relationship tests to dimensions.
- Sources: freshness configured on every source.

## Documentation

- Every model and every gold column has a description (enforced by dbt-checkpoint).
- Describe the grain in the first sentence of a model description: "One row per ...".
