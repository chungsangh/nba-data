{#-
    One row per team per completed game (two per game), excluding All-Star games. Box score
    counting stats come from ESPN's team box score; possessions come from play-by-play, which is
    more accurate than the usual FGA - ORB + TOV + 0.44 * FTA estimate.
-#}

with

box as (

    select * from {{ ref('stg_espn__team_boxscores') }}

),

games as (

    select * from {{ ref('int_games_classified') }}
    where not is_all_star

),

possessions as (

    select
        game_id,
        offense_team_id as team_id,
        count(*) as possessions,
        sum(duration_seconds) as possession_seconds
    from {{ ref('int_possessions_summarized') }}
    group by all

),

joined as (

    select
        box.*,
        games.game_date,
        games.season_type,
        games.playoff_round,
        games.counts_toward_record,
        possessions.possessions,
        opp_possessions.possessions as opponent_possessions,
        opp.field_goals_attempted as opponent_field_goals_attempted,
        opp.three_point_field_goals_made as opponent_three_point_field_goals_made,
        opp.field_goals_made as opponent_field_goals_made,
        opp.free_throws_attempted as opponent_free_throws_attempted,
        opp.offensive_rebounds as opponent_offensive_rebounds,
        opp.defensive_rebounds as opponent_defensive_rebounds,
        opp.turnovers as opponent_turnovers
    from box
    inner join games
        on box.game_id = games.game_id
    inner join {{ ref('stg_espn__team_boxscores') }} as opp
        on box.game_id = opp.game_id and box.opponent_team_id = opp.team_id
    left join possessions
        on box.game_id = possessions.game_id and box.team_id = possessions.team_id
    left join possessions as opp_possessions
        on box.game_id = opp_possessions.game_id and box.opponent_team_id = opp_possessions.team_id

),

final as (

    select
        -- keys
        cast(team_game_id as varchar) as team_game_id,
        cast(game_id as integer) as game_id,
        cast(team_id as integer) as team_id,
        cast(opponent_team_id as integer) as opponent_team_id,

        -- context
        cast(game_date as date) as game_date,
        cast(season as integer) as season,
        cast(season_type as varchar) as season_type,
        cast(playoff_round as varchar) as playoff_round,
        cast(is_home as boolean) as is_home,
        cast(counts_toward_record as boolean) as counts_toward_record,

        -- result
        cast(is_winner as boolean) as is_win,
        cast(points as integer) as points,
        cast(opponent_points as integer) as opponent_points,
        cast(points - opponent_points as integer) as point_differential,

        -- tempo
        cast(possessions as integer) as possessions,
        cast(opponent_possessions as integer) as opponent_possessions,

        -- shooting
        cast(field_goals_made as integer) as field_goals_made,
        cast(field_goals_attempted as integer) as field_goals_attempted,
        cast(three_point_field_goals_made as integer) as three_pointers_made,
        cast(three_point_field_goals_attempted as integer) as three_pointers_attempted,
        cast(free_throws_made as integer) as free_throws_made,
        cast(free_throws_attempted as integer) as free_throws_attempted,

        -- other counting stats
        cast(offensive_rebounds as integer) as offensive_rebounds,
        cast(defensive_rebounds as integer) as defensive_rebounds,
        cast(assists as integer) as assists,
        cast(steals as integer) as steals,
        cast(blocks as integer) as blocks,
        cast(turnovers as integer) as turnovers,
        cast(fouls as integer) as fouls,
        cast(fast_break_points as integer) as fast_break_points,
        cast(points_in_paint as integer) as points_in_paint,
        cast(points_off_turnovers as integer) as points_off_turnovers,

        -- opponent stats needed for four-factor metrics
        cast(opponent_field_goals_made as integer) as opponent_field_goals_made,
        cast(opponent_field_goals_attempted as integer) as opponent_field_goals_attempted,
        cast(opponent_three_point_field_goals_made as integer) as opponent_three_pointers_made,
        cast(opponent_free_throws_attempted as integer) as opponent_free_throws_attempted,
        cast(opponent_offensive_rebounds as integer) as opponent_offensive_rebounds,
        cast(opponent_defensive_rebounds as integer) as opponent_defensive_rebounds,
        cast(opponent_turnovers as integer) as opponent_turnovers

    from joined

)

select * from final
