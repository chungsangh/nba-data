{#-
    One row per possession: who had the ball, how it started and ended, and what it produced.
    Points count only the offense's scoring; technical free throws by the defense are excluded.
-#}

with

plays as (

    select * from {{ ref('int_plays_sequenced') }}
    where possession_number is not null

),

possession_events as (

    select * from plays
    where is_possession_event

),

bounds as (

    select
        game_id,
        possession_number,
        -- the first possession event's team_id is the offense for the whole possession
        arg_min(team_id, play_index) as offense_team_id,
        any_value(home_team_id) as home_team_id,
        any_value(away_team_id) as away_team_id,
        any_value(season) as season,
        any_value(season_type) as season_type,
        any_value(game_date) as game_date,
        any_value(game_start_at_utc) as game_start_at_utc,
        min(period) as period,
        min(play_index) as start_play_index,
        max(play_index) as end_play_index,
        arg_min(play_category, play_index) as first_event_category,
        arg_max(play_category, play_index) as last_event_category,
        arg_max(is_scoring_play, play_index) as last_event_scored
    from possession_events
    group by game_id, possession_number

),

stats as (

    select
        plays.game_id,
        plays.possession_number,
        max(plays.game_seconds_elapsed) as ended_at_game_seconds,
        sum(case
            when plays.team_id = bounds.offense_team_id and plays.is_scoring_play
                and plays.play_category in ('field_goal', 'free_throw')
                then plays.points_scored
            else 0
        end) as points,
        count(*) filter (
            where plays.play_category = 'field_goal' and plays.team_id = bounds.offense_team_id
        ) as field_goals_attempted,
        count(*) filter (
            where plays.play_category = 'field_goal' and plays.team_id = bounds.offense_team_id
            and plays.is_scoring_play
        ) as field_goals_made,
        count(*) filter (
            where plays.play_category = 'field_goal' and plays.team_id = bounds.offense_team_id
            and plays.points_attempted = 3
        ) as three_pointers_attempted,
        count(*) filter (
            where plays.play_category = 'free_throw' and plays.team_id = bounds.offense_team_id
        ) as free_throws_attempted,
        count(*) filter (
            where plays.play_category = 'offensive_rebound'
            and plays.team_id = bounds.offense_team_id
        ) as offensive_rebounds,
        count(*) filter (
            where plays.play_category = 'turnover' and plays.team_id = bounds.offense_team_id
        ) as turnovers
    from plays
    inner join bounds
        on
            plays.game_id = bounds.game_id
            and plays.possession_number = bounds.possession_number
    group by plays.game_id, plays.possession_number

),

with_previous as (

    select
        bounds.*,
        stats.ended_at_game_seconds,
        lag(bounds.last_event_category) over game_possessions as previous_end_category,
        lag(bounds.last_event_scored) over game_possessions as previous_end_scored,
        lag(bounds.period) over game_possessions as previous_period,
        lag(stats.ended_at_game_seconds) over game_possessions as previous_ended_at_game_seconds
    from bounds
    inner join stats
        on
            bounds.game_id = stats.game_id
            and bounds.possession_number = stats.possession_number
    window game_possessions as (partition by bounds.game_id order by bounds.possession_number)

),

timed as (

    select
        *,
        previous_period is null or previous_period <> period as is_period_start,
        -- A possession starts when the previous one ended (the ball changed hands), not at the
        -- offense's first recorded event; at a period start it starts at the period's 0:00.
        case
            when previous_period is null or previous_period <> period
                then
                    case when period <= 4 then (period - 1) * 720 else 2880 + (period - 5) * 300 end
            else previous_ended_at_game_seconds
        end as started_at_game_seconds
    from with_previous

),

final as (

    select
        -- keys
        {{ dbt_utils.generate_surrogate_key(['timed.game_id', 'timed.possession_number']) }}
            as possession_id,
        timed.game_id,
        timed.possession_number,
        timed.offense_team_id,
        case
            when timed.offense_team_id = timed.home_team_id then timed.away_team_id
            else timed.home_team_id
        end as defense_team_id,

        -- context
        timed.season,
        timed.season_type,
        timed.game_date,
        timed.game_start_at_utc,
        timed.period,

        -- how it started
        case
            when timed.is_period_start then 'period_start'
            when timed.first_event_category = 'defensive_rebound' then 'defensive_rebound'
            when timed.previous_end_category = 'turnover' then 'turnover'
            when timed.previous_end_scored then 'opponent_score'
            else 'other'
        end as start_reason,

        -- timing
        timed.start_play_index,
        timed.end_play_index,
        timed.started_at_game_seconds,
        timed.ended_at_game_seconds,
        timed.ended_at_game_seconds - timed.started_at_game_seconds as duration_seconds,

        -- outcome (technical free throws excluded: they are not part of a possession)
        stats.points,
        stats.field_goals_attempted,
        stats.field_goals_made,
        stats.three_pointers_attempted,
        stats.free_throws_attempted,
        stats.offensive_rebounds,
        stats.turnovers,
        stats.points > 0 as is_scoring_possession

    from timed
    inner join stats
        on
            timed.game_id = stats.game_id
            and timed.possession_number = stats.possession_number

)

select * from final
