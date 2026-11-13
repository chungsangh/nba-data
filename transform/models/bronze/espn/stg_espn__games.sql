with

source as (

    select * from {{ source('espn', 'espn_nba_schedules') }}

),

renamed as (

    select
        -- keys
        game_id,
        home_id as home_team_id,
        away_id as away_team_id,
        venue_id,

        -- season context
        season,
        season_type as season_type_id,
        case season_type
            {%- for type_id, label in var('season_types').items() %}
                when {{ type_id }} then '{{ label }}'
            {%- endfor %}
            else 'other'
        end as season_type,
        type_abbreviation as game_type_code,
        nullif(trim(notes_headline), '') as game_note,

        -- status: STATUS_FINAL -> final
        lower(replace(status_type_name, 'STATUS_', '')) as game_status,
        coalesce(status_type_completed, false) as is_completed,
        coalesce(play_by_play_available, false) as has_play_by_play,

        -- time: ESPN sends ISO strings in UTC, e.g. '2026-10-20T23:00Z'
        timezone('UTC', try_cast(replace(start_date, 'Z', ':00Z') as timestamptz))
            as scheduled_start_at_utc,

        -- result (NULL until the game is played)
        home_score,
        away_score,
        home_winner as is_home_winner,

        -- venue
        venue_full_name as venue_name,
        venue_address_city as venue_city,
        venue_address_state as venue_state,
        coalesce(neutral_site, false) as is_neutral_site,
        cast(attendance as integer) as attendance,
        nullif(broadcast_name, '') as broadcast_network,

        -- lineage
        _loaded_at,
        _source_published_at

    from source

)

select * from renamed
