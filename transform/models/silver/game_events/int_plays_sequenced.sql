{#-
    One row per play, in true chronological order, with game-clock math, play categories and a
    possession number.

    Possession logic: for possession events (shots, free throws, turnovers, rebounds) ESPN's team_id
    is the team with the ball - including defensive rebounds, where the rebounding team just gained
    it. So a new possession starts whenever that team changes, or a new period starts. Other plays
    (fouls, substitutions, timeouts) inherit the possession that was in progress.
-#}

with

plays as (

    select * from {{ ref('stg_espn__plays') }}

),

play_types as (

    select * from {{ ref('play_type_categories') }}

),

classified as (

    select
        plays.*,
        coalesce(play_types.play_category, 'other') as play_category,
        coalesce(play_types.is_possession_event, false) and plays.team_id is not null
            as is_possession_event,
        -- ESPN's sequence_number is not chronological; game_play_number is.
        row_number() over (
            partition by plays.game_id
            order by plays.game_play_number, plays.play_id
        ) as play_index
    from plays
    left join play_types
        on plays.play_type_id = play_types.play_type_id

),

clock as (

    select
        *,
        -- regulation periods are 12 minutes, overtimes 5
        case when period <= 4 then 720 else 300 end as period_length_seconds,
        case
            when period <= 4 then (period - 1) * 720
            else 2880 + (period - 5) * 300
        end
        + (case when period <= 4 then 720 else 300 end) - period_seconds_remaining
            as game_seconds_elapsed
    from classified

),

possession_changes as (

    select
        *,
        case
            -- possession events always carry a team_id, so -1 can only mean "no previous event"
            when not is_possession_event then null
            when
                coalesce(
                    lag(team_id) over (
                        partition by game_id, is_possession_event order by play_index
                    ),
                    -1
                ) <> team_id
                then 1
            when
                coalesce(
                    lag(period) over (
                        partition by game_id, is_possession_event order by play_index
                    ),
                    -1
                ) <> period
                then 1
            else 0
        end as is_new_possession
    from clock

),

numbered as (

    select
        *,
        -- running count of possession starts; non-possession plays add 0 and so carry the
        -- possession in progress. Plays before the first possession (tip-off) get NULL.
        nullif(sum(coalesce(is_new_possession, 0)) over game_so_far, 0) as possession_number
    from possession_changes
    window game_so_far as (
        partition by game_id
        order by play_index
        rows between unbounded preceding and current row
    )

),

final as (

    select
        -- keys
        play_id,
        game_id,
        play_index,
        possession_number,
        team_id,
        primary_athlete_id,
        secondary_athlete_id,
        tertiary_athlete_id,

        -- context
        season,
        season_type,
        game_date,
        game_start_at_utc,

        -- clock
        period,
        clock_display,
        period_seconds_remaining,
        game_seconds_elapsed,

        -- event
        play_type_id,
        play_type,
        play_category,
        play_description,
        is_possession_event,
        is_scoring_play,
        is_shooting_play,
        points_scored,
        points_attempted,
        home_score,
        away_score,
        home_team_id,
        away_team_id,
        shot_x,
        shot_y

    from numbered

)

select * from final
