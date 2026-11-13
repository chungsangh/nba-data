{{ config(severity='warn', tags=['known_issue']) }}

-- Ordering plays by game_play_number (int_plays_sequenced.play_index) instead of ESPN's
-- sequence_number cut backwards-score rows from ~4,600 to ~24 across two seasons. The remainder
-- are upstream score corrections (e.g. a basket overturned on review). Kept as a warning so the
-- count is visible on every run.

with ordered as (

    select
        game_id,
        play_id,
        play_index,
        home_score,
        away_score,
        lag(home_score) over game_order as prev_home_score,
        lag(away_score) over game_order as prev_away_score
    from {{ ref('int_plays_sequenced') }}
    window game_order as (partition by game_id order by play_index)

)

select *
from ordered
where home_score < prev_home_score or away_score < prev_away_score
