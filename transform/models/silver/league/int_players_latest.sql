{#-
    One row per player with the attributes from their most recent game. This is the source for
    the snap_players snapshot, which records each change (trade, new jersey, position change).
-#}

with

player_box as (

    select player_box.*
    from {{ ref('stg_espn__player_boxscores') }} as player_box
    inner join {{ ref('int_games_classified') }} as games
        on player_box.game_id = games.game_id
    where not games.is_all_star

),

final as (

    select
        player_id,
        arg_max(player_name, game_date) as player_name,
        arg_max(player_short_name, game_date) as player_short_name,
        arg_max(team_id, game_date) as team_id,
        arg_max(jersey_number, game_date) as jersey_number,
        arg_max(position, game_date) as position,
        arg_max(headshot_url, game_date) as headshot_url,
        max(game_date) as last_game_date
    from player_box
    group by player_id

)

select * from final
