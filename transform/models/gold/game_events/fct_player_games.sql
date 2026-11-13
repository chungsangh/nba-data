{#- One row per player per game they were on the roster for, excluding All-Star games. -#}

with

box as (

    select * from {{ ref('stg_espn__player_boxscores') }}

),

games as (

    select * from {{ ref('int_games_classified') }}
    where not is_all_star

),

final as (

    select
        -- keys
        cast(box.player_game_id as varchar) as player_game_id,
        cast(box.game_id as integer) as game_id,
        cast(box.player_id as integer) as player_id,
        cast(box.team_id as integer) as team_id,
        cast(box.opponent_team_id as integer) as opponent_team_id,

        -- context
        cast(games.game_date as date) as game_date,
        cast(games.season as integer) as season,
        cast(games.season_type as varchar) as season_type,
        cast(box.is_home as boolean) as is_home,
        cast(box.is_starter as boolean) as is_starter,
        cast(box.did_not_play as boolean) as did_not_play,
        cast(box.did_not_play_reason as varchar) as did_not_play_reason,

        -- box score
        cast(box.minutes_played as double) as minutes_played,
        cast(box.points as integer) as points,
        cast(box.field_goals_made as integer) as field_goals_made,
        cast(box.field_goals_attempted as integer) as field_goals_attempted,
        cast(box.three_point_field_goals_made as integer) as three_pointers_made,
        cast(box.three_point_field_goals_attempted as integer) as three_pointers_attempted,
        cast(box.free_throws_made as integer) as free_throws_made,
        cast(box.free_throws_attempted as integer) as free_throws_attempted,
        cast(box.offensive_rebounds as integer) as offensive_rebounds,
        cast(box.defensive_rebounds as integer) as defensive_rebounds,
        cast(box.assists as integer) as assists,
        cast(box.steals as integer) as steals,
        cast(box.blocks as integer) as blocks,
        cast(box.turnovers as integer) as turnovers,
        cast(box.fouls as integer) as fouls,
        cast(box.plus_minus as integer) as plus_minus

    from box
    inner join games
        on box.game_id = games.game_id

)

select * from final
