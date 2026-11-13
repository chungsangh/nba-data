with

games as (

    select * from {{ ref('int_games_classified') }}

),

final as (

    select
        cast(game_id as integer) as game_id,
        cast(season as integer) as season,
        cast(season_type as varchar) as season_type,
        cast(playoff_round as varchar) as playoff_round,
        cast(game_date as date) as game_date,
        cast(scheduled_start_at_utc as timestamp) as scheduled_start_at_utc,
        cast(game_status as varchar) as game_status,
        cast(is_completed as boolean) as is_completed,
        cast(is_all_star as boolean) as is_all_star,
        cast(is_cup_championship as boolean) as is_cup_championship,
        cast(counts_toward_record as boolean) as counts_toward_record,
        cast(home_team_id as integer) as home_team_id,
        cast(away_team_id as integer) as away_team_id,
        cast(home_score as integer) as home_score,
        cast(away_score as integer) as away_score,
        cast(winning_team_id as integer) as winning_team_id,
        cast(venue_name as varchar) as venue_name,
        cast(venue_city as varchar) as venue_city,
        cast(is_neutral_site as boolean) as is_neutral_site,
        cast(attendance as integer) as attendance,
        cast(broadcast_network as varchar) as broadcast_network,
        cast(game_note as varchar) as game_note
    from games

)

select * from final
