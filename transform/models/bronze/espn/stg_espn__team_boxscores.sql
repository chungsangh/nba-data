with

source as (

    select * from {{ source('espn', 'espn_nba_team_boxscores') }}

),

renamed as (

    select
        -- keys
        {{ dbt_utils.generate_surrogate_key(['game_id', 'team_id']) }} as team_game_id,
        game_id,
        team_id,
        opponent_team_id,

        -- season context
        season,
        season_type as season_type_id,
        game_date,

        -- team attributes as of this game
        team_abbreviation,
        team_location,
        team_name,
        team_display_name,
        team_slug,
        team_color,
        team_alternate_color,
        team_logo as team_logo_url,

        -- result
        team_home_away = 'home' as is_home,
        team_score as points,
        opponent_team_score as opponent_points,
        coalesce(team_winner, false) as is_winner,

        -- box score
        field_goals_made,
        field_goals_attempted,
        three_point_field_goals_made,
        three_point_field_goals_attempted,
        free_throws_made,
        free_throws_attempted,
        offensive_rebounds,
        defensive_rebounds,
        total_rebounds as rebounds,
        assists,
        steals,
        blocks,
        -- turnovers = player turnovers; total adds team turnovers (e.g. shot clock)
        turnovers as player_turnovers,
        total_turnovers as turnovers,
        fouls,
        total_technical_fouls as technical_fouls,
        flagrant_fouls,
        -- ESPN sends these as text
        try_cast(fast_break_points as integer) as fast_break_points,
        try_cast(points_in_paint as integer) as points_in_paint,
        try_cast(turnover_points as integer) as points_off_turnovers,
        try_cast(largest_lead as integer) as largest_lead,

        -- lineage
        _loaded_at,
        _source_published_at

    from source

)

select * from renamed
