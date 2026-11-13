{{ config(severity='error', error_if='>10', warn_if='>0', tags=['reconciliation']) }}

-- Known-answer test: a team's points in the box score should equal the points on its scoring
-- plays in play-by-play. Two independent ESPN feeds agree for >99.8% of team-games; a handful of
-- games have incomplete play-by-play. More than 10 mismatches means something broke (ingestion,
-- play classification, or an All-Star filter), so the build fails.

with play_by_play as (

    select
        game_id,
        team_id,
        sum(points_scored) as pbp_points
    from {{ ref('int_plays_sequenced') }}
    where is_scoring_play
    group by game_id, team_id

)

select
    team_games.game_id,
    team_games.team_id,
    team_games.points as box_score_points,
    play_by_play.pbp_points
from {{ ref('fct_team_games') }} as team_games
left join play_by_play
    on
        team_games.game_id = play_by_play.game_id
        and team_games.team_id = play_by_play.team_id
where play_by_play.pbp_points is distinct from team_games.points
