{#-
    One row per field goal attempt, excluding All-Star games.

    Microbatch incremental: dbt processes one day of games per batch, keyed on tip-off time, and
    re-runs the previous `lookback` days each time so late stat corrections are picked up.
    Backfill any range with: dbt run -s fct_shots --event-time-start 2026-01-01 --event-time-end 2026-02-01
-#}

{{
    config(
        materialized='incremental',
        incremental_strategy='microbatch',
        event_time='game_start_at_utc',
        batch_size='day',
        lookback=3,
        begin=var('date_spine_start'),
        on_schema_change='fail'
    )
}}

with

shots as (

    -- dbt filters this ref to the batch's time window via the upstream event_time config
    select * from {{ ref('int_shots_located') }}

),

games as (

    select game_id from {{ ref('int_games_classified') }}
    where not is_all_star

),

final as (

    select
        -- keys
        cast(shots.shot_id as bigint) as shot_id,
        cast(shots.game_id as integer) as game_id,
        cast(shots.possession_number as integer) as possession_number,
        cast(shots.team_id as integer) as team_id,
        cast(shots.shooter_player_id as integer) as shooter_player_id,
        cast(shots.assisting_player_id as integer) as assisting_player_id,
        cast(shots.blocking_player_id as integer) as blocking_player_id,

        -- context
        cast(shots.game_date as date) as game_date,
        cast(shots.game_start_at_utc as timestamp) as game_start_at_utc,
        cast(shots.season as integer) as season,
        cast(shots.season_type as varchar) as season_type,
        cast(shots.period as integer) as period,
        cast(shots.game_seconds_elapsed as double) as game_seconds_elapsed,

        -- shot
        cast(shots.shot_type as varchar) as shot_type,
        cast(shots.shot_value as integer) as shot_value,
        cast(shots.shot_zone as varchar) as shot_zone,
        cast(shots.shot_distance_ft as double) as shot_distance_ft,
        cast(shots.shot_x as double) as shot_x,
        cast(shots.shot_y as double) as shot_y,
        cast(shots.is_made as boolean) as is_made,
        cast(shots.points as integer) as points

    from shots
    inner join games
        on shots.game_id = games.game_id

)

select * from final
