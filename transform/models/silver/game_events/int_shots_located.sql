{#-
    One row per field goal attempt with distance and court zone.

    ESPN coordinates are feet from center court; baskets sit 5.25 ft in from each baseline, at
    x = +/-41.75. Teams switch baskets at halftime, so each team's basket for a half is the side
    where most of its shots that half landed (99.5% of shots agree). Using that side, rather than
    abs(x), keeps backcourt heaves from being measured to the wrong basket.
-#}

{%- set basket_x = 41.75 -%}

with

shots as (

    select * from {{ ref('int_plays_sequenced') }}
    where play_category = 'field_goal' and shot_x is not null

),

basket_side as (

    select
        game_id,
        team_id,
        period <= 2 as is_first_half,
        sign(median(shot_x)) as basket_sign
    from shots
    group by all

),

measured as (

    select
        shots.*,
        basket_side.basket_sign,
        sqrt(
            power(shots.shot_x - basket_side.basket_sign * {{ basket_x }}, 2)
            + power(shots.shot_y, 2)
        ) as shot_distance_ft,
        sign(shots.shot_x) <> basket_side.basket_sign as is_from_backcourt
    from shots
    inner join basket_side
        on
            shots.game_id = basket_side.game_id
            and shots.team_id = basket_side.team_id
            and (shots.period <= 2) = basket_side.is_first_half

),

final as (

    select
        -- keys
        play_id as shot_id,
        game_id,
        play_index,
        possession_number,
        team_id,
        primary_athlete_id as shooter_player_id,
        case
            when is_scoring_play then secondary_athlete_id
        end as assisting_player_id,
        -- on a blocked miss ESPN puts the blocker in athlete slot 2
        case
            when not is_scoring_play and play_description ilike '% blocks %'
                then secondary_athlete_id
        end as blocking_player_id,

        -- context
        season,
        season_type,
        game_date,
        game_start_at_utc,
        period,
        game_seconds_elapsed,

        -- shot
        play_type as shot_type,
        points_attempted as shot_value,
        is_scoring_play as is_made,
        case when is_scoring_play then points_scored else 0 end as points,
        shot_x,
        shot_y,
        round(shot_distance_ft, 1) as shot_distance_ft,
        case
            when is_from_backcourt then 'backcourt'
            when points_attempted = 3 and abs(shot_y) >= 22 then 'corner_three'
            when points_attempted = 3 then 'above_break_three'
            when shot_distance_ft < 4 then 'restricted_area'
            -- the paint: 16 ft wide, 19 ft from the baseline
            when abs(shot_y) <= 8 and abs(shot_x) >= 47 - 19 then 'paint'
            else 'mid_range'
        end as shot_zone

    from measured

)

select * from final
