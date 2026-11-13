with

team_games as (

    select team_box.*
    from {{ ref('stg_espn__team_boxscores') }} as team_box
    inner join {{ ref('int_games_classified') }} as games
        on team_box.game_id = games.game_id
    -- All-Star "teams" are not franchises
    where not games.is_all_star

),

final as (

    select
        cast(team_id as integer) as team_id,
        cast(arg_max(team_abbreviation, game_date) as varchar) as team_abbreviation,
        cast(arg_max(team_location, game_date) as varchar) as team_location,
        cast(arg_max(team_name, game_date) as varchar) as team_name,
        cast(arg_max(team_display_name, game_date) as varchar) as team_display_name,
        cast(arg_max(team_color, game_date) as varchar) as team_color,
        cast(arg_max(team_logo_url, game_date) as varchar) as team_logo_url
    from team_games
    group by team_id

)

select * from final
