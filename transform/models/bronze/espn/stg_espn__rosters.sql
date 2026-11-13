with

source as (

    select * from {{ source('espn', 'espn_nba_rosters') }}

),

renamed as (

    select
        -- keys
        cast(athlete_id as integer) as player_id,
        team_id,
        season,

        -- player
        display_name as player_name,
        short_name as player_short_name,
        first_name,
        last_name,
        nullif(jersey, '') as jersey_number,
        nullif(position_abbreviation, '') as position,
        lower(status_type) as roster_status,
        headshot_href as headshot_url,

        -- bio: ESPN sends text like 6' 5" and 205 lbs
        try_cast(regexp_extract(height, '^(\d+)''', 1) as integer) * 12
        + try_cast(regexp_extract(height, '(\d+)"', 1) as integer) as height_inches,
        try_cast(regexp_extract(weight, '^(\d+)', 1) as integer) as weight_lbs,
        try_cast(left(date_of_birth, 10) as date) as birth_date,
        nullif(birth_place_country, '') as birth_country,
        try_cast(experience_years as integer) as experience_years,

        -- lineage
        _loaded_at,
        _source_published_at

    from source

)

select * from renamed
