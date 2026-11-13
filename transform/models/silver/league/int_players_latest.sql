{#-
    One row per known player with their current attributes. Source for the snap_players snapshot,
    which records each change (trade, signing, release, new jersey, position change).

    The current-season roster is authoritative for team, jersey and position: it shows signings
    and trades before the player appears in a game. Box scores fill in players no longer on a
    roster; their team_id is NULL (free agent or retired) and last_game_team_id keeps where they
    last played.
-#}

with

current_roster as (

    select rosters.*
    from {{ ref('stg_espn__rosters') }} as rosters
    where rosters.season = (
            select max(all_rosters.season) from {{ ref('stg_espn__rosters') }} as all_rosters
        )

),

player_box as (

    select player_box.*
    from {{ ref('stg_espn__player_boxscores') }} as player_box
    inner join {{ ref('int_games_classified') }} as games
        on player_box.game_id = games.game_id
    where not games.is_all_star

),

last_game as (

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

),

final as (

    select
        coalesce(current_roster.player_id, last_game.player_id) as player_id,
        coalesce(current_roster.player_name, last_game.player_name) as player_name,
        coalesce(current_roster.player_short_name, last_game.player_short_name)
            as player_short_name,

        -- current affiliation: roster only
        current_roster.team_id,
        current_roster.player_id is not null as is_on_current_roster,
        coalesce(current_roster.jersey_number, last_game.jersey_number) as jersey_number,
        coalesce(current_roster.position, last_game.position) as position,
        coalesce(current_roster.headshot_url, last_game.headshot_url) as headshot_url,

        -- bio (roster only)
        current_roster.height_inches,
        current_roster.weight_lbs,
        current_roster.birth_date,
        current_roster.birth_country,
        current_roster.experience_years,

        -- playing history
        last_game.team_id as last_game_team_id,
        last_game.last_game_date

    from current_roster
    full outer join last_game
        on current_roster.player_id = last_game.player_id

)

select * from final
