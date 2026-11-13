with

source as (

    select * from {{ source('espn', 'espn_nba_plays') }}

),

renamed as (

    select
        -- keys
        id as play_id,
        game_id,
        team_id,
        home_team_id,
        away_team_id,
        athlete_id_1 as primary_athlete_id,
        athlete_id_2 as secondary_athlete_id,
        athlete_id_3 as tertiary_athlete_id,

        -- season context
        season,
        season_type as season_type_id,
        case season_type
            {%- for type_id, label in var('season_types').items() %}
                when {{ type_id }} then '{{ label }}'
            {%- endfor %}
            else 'other'
        end as season_type,

        -- ordering and game clock
        sequence_number,
        game_play_number,
        period_number as period,
        clock_display_value as clock_display,
        clock_minutes * 60 + clock_seconds as period_seconds_remaining,

        -- what happened
        type_id as play_type_id,
        -- ESPN embeds line breaks in some labels, e.g. 'Bad Pass\nTurnover'
        trim(regexp_replace(type_text, '\s+', ' ', 'g')) as play_type,
        text as play_description,
        coalesce(scoring_play, false) as is_scoring_play,
        coalesce(shooting_play, false) as is_shooting_play,
        score_value as points_scored,
        points_attempted,
        home_score,
        away_score,

        -- shot location in feet; ESPN uses a large sentinel for non-shot plays
        case when shooting_play then coordinate_x end as shot_x,
        case when shooting_play then coordinate_y end as shot_y,

        -- time, normalized to UTC so nothing depends on the session time zone
        game_date,
        timezone('UTC', game_date_time) as game_start_at_utc,
        timezone('UTC', try_cast(wallclock as timestamptz)) as wallclock_at_utc,

        -- lineage
        _loaded_at,
        _source_published_at

    from source

)

select * from renamed
