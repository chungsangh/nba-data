{{ config(tags=['reconciliation']) }}

-- Every completed, non-All-Star game with a box score must have exactly one row per team in
-- fct_team_games, with mirrored results (one win, one loss; points equal opponent_points).

with team_rows as (

    select
        game_id,
        count(*) as team_rows,
        count(*) filter (where is_win) as wins,
        count(*) filter (where points = opponent_points) as ties_recorded
    from {{ ref('fct_team_games') }}
    group by game_id

)

select *
from team_rows
where team_rows <> 2 or wins <> 1 or ties_recorded > 0
