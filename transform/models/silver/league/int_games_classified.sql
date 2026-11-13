with

games as (

    select * from {{ ref('stg_espn__games') }}

),

final as (

    select
        game_id,
        season,
        season_type,
        game_type_code,
        case game_type_code
            when 'RD16' then 'first_round'
            when 'QTR' then 'conference_semifinals'
            when 'SEMI' then 'conference_finals'
            when 'FINAL' then 'finals'
        end as playoff_round,
        game_type_code = 'ALLSTAR' as is_all_star,
        game_type_code = 'CC' as is_cup_championship,
        -- the NBA Cup final and All-Star games do not count toward team records
        game_type_code not in ('ALLSTAR', 'CC') as counts_toward_record,
        game_note,
        game_status,
        is_completed,
        has_play_by_play,
        scheduled_start_at_utc,
        -- the league schedules by US Eastern date
        cast(timezone('America/New_York', scheduled_start_at_utc at time zone 'UTC') as date)
            as game_date,
        home_team_id,
        away_team_id,
        home_score,
        away_score,
        case
            when is_completed and home_score > away_score then home_team_id
            when is_completed and away_score > home_score then away_team_id
        end as winning_team_id,
        venue_id,
        venue_name,
        venue_city,
        venue_state,
        is_neutral_site,
        attendance,
        broadcast_network
    from games

)

select * from final
