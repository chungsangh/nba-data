{{ config(severity='warn', tags=['known_issue']) }}

-- Known upstream issue: in ESPN's sequence_number order, the running score sometimes goes
-- backwards (out-of-order rows or score corrections). Tracked as a warning so the count is
-- visible on every run; the silver play-ordering model is responsible for resolving it.

with ordered as (

    select
        game_id,
        play_id,
        home_score,
        away_score,
        lag(home_score) over (partition by game_id order by sequence_number, play_id) as prev_home,
        lag(away_score) over (partition by game_id order by sequence_number, play_id) as prev_away
    from {{ ref('stg_espn__plays') }}

)

select *
from ordered
where home_score < prev_home or away_score < prev_away
