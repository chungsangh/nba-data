{{ config(severity='warn', tags=['reconciliation']) }}

-- Sanity check on the possession builder: play-by-play possessions should be close to the
-- standard box-score estimate FGA - ORB + TOV + 0.44 * FTA. Typical gap is ~3; a gap above 12
-- points to a broken game feed or a possession-logic bug worth looking at.

select
    game_id,
    team_id,
    possessions,
    round(
        field_goals_attempted - offensive_rebounds + turnovers + 0.44 * free_throws_attempted, 1
    ) as estimated_possessions
from {{ ref('fct_team_games') }}
where
    abs(
        possessions
        - (field_goals_attempted - offensive_rebounds + turnovers + 0.44 * free_throws_attempted)
    ) > 12
