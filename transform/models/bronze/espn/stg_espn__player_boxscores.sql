with

source as (

    select * from {{ source('espn', 'espn_nba_player_boxscores') }}

),

renamed as (

    select
        -- keys
        {{ dbt_utils.generate_surrogate_key(['game_id', 'athlete_id']) }} as player_game_id,
        game_id,
        athlete_id as player_id,
        team_id,
        opponent_team_id,

        -- season context
        season,
        season_type as season_type_id,
        game_date,

        -- player attributes as of this game
        athlete_display_name as player_name,
        athlete_short_name as player_short_name,
        nullif(athlete_jersey, '') as jersey_number,
        nullif(athlete_position_abbreviation, '') as position,
        athlete_headshot_href as headshot_url,

        -- participation
        home_away = 'home' as is_home,
        coalesce(starter, false) as is_starter,
        coalesce(did_not_play, false) as did_not_play,
        nullif(reason, '') as did_not_play_reason,
        coalesce(ejected, false) as was_ejected,

        -- box score
        minutes as minutes_played,
        points,
        field_goals_made,
        field_goals_attempted,
        three_point_field_goals_made,
        three_point_field_goals_attempted,
        free_throws_made,
        free_throws_attempted,
        offensive_rebounds,
        defensive_rebounds,
        rebounds,
        assists,
        steals,
        blocks,
        turnovers,
        fouls,
        -- ESPN sends '+2' / '-4' / '0' as text
        try_cast(replace(plus_minus, '+', '') as integer) as plus_minus,

        -- lineage
        _loaded_at,
        _source_published_at

    from source
    -- ESPN emits a few empty placeholder rows (no athlete, name, minutes or points)
    where athlete_id is not null

)

select * from renamed
