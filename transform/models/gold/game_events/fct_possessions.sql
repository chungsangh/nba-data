{#-
    One row per possession, excluding All-Star games.

    Incremental (merge on possession_id). Each run reprocesses games from the last
    `possession_lookback_days` days, so ESPN stat corrections published after a game - which
    replace that season's rows upstream - flow into already-loaded possessions. A full refresh
    rebuilds everything.
-#}

{{
    config(
        materialized='incremental',
        unique_key='possession_id',
        incremental_strategy='delete+insert',
        on_schema_change='fail'
    )
}}

with

possessions as (

    select * from {{ ref('int_possessions_summarized') }}
    {% if is_incremental() %}
        where game_date >= (
            select max(game_date) - interval '{{ var("possession_lookback_days") }} days'
            from {{ this }}
        )
    {% endif %}

),

games as (

    select game_id from {{ ref('int_games_classified') }}
    where not is_all_star

),

final as (

    select
        -- keys
        cast(possessions.possession_id as varchar) as possession_id,
        cast(possessions.game_id as integer) as game_id,
        cast(possessions.possession_number as integer) as possession_number,
        cast(possessions.offense_team_id as integer) as offense_team_id,
        cast(possessions.defense_team_id as integer) as defense_team_id,

        -- context
        cast(possessions.game_date as date) as game_date,
        cast(possessions.season as integer) as season,
        cast(possessions.season_type as varchar) as season_type,
        cast(possessions.period as integer) as period,
        cast(possessions.start_reason as varchar) as start_reason,

        -- timing
        cast(possessions.started_at_game_seconds as double) as started_at_game_seconds,
        cast(possessions.duration_seconds as double) as duration_seconds,

        -- outcome
        cast(possessions.points as integer) as points,
        cast(possessions.is_scoring_possession as boolean) as is_scoring_possession,
        cast(possessions.field_goals_attempted as integer) as field_goals_attempted,
        cast(possessions.field_goals_made as integer) as field_goals_made,
        cast(possessions.three_pointers_attempted as integer) as three_pointers_attempted,
        cast(possessions.free_throws_attempted as integer) as free_throws_attempted,
        cast(possessions.offensive_rebounds as integer) as offensive_rebounds,
        cast(possessions.turnovers as integer) as turnovers

    from possessions
    inner join games
        on possessions.game_id = games.game_id

)

select * from final
