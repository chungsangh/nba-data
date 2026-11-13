{#-
    One row per player version. Team, jersey, position and name are type 2 (from the snapshot);
    roster status and bio are type 1 (today's values on every version). Join facts on player_id
    with is_current for today's attributes, or on player_id and the fact date between valid_from
    and valid_to for history.
    A player's first version is valid from 1900-01-01 (see the valid_from comment).
-#}

with

snapshot as (

    select * from {{ ref('snap_players') }}

),

-- Type 1 attributes: bio and current roster status describe the player today, so every version
-- shows the latest values. Taking them from the source instead of the snapshot also means new
-- columns never depend on old snapshot rows being back-filled (they would be NULL).
current_attributes as (

    select * from {{ ref('int_players_latest') }}

),

final as (

    select
        cast(snapshot.dbt_scd_id as varchar) as player_version_id,
        cast(snapshot.player_id as integer) as player_id,
        cast(snapshot.player_name as varchar) as player_name,
        cast(snapshot.player_short_name as varchar) as player_short_name,
        cast(snapshot.team_id as integer) as team_id,
        cast(snapshot.jersey_number as varchar) as jersey_number,
        cast(snapshot.position as varchar) as position,
        cast(snapshot.headshot_url as varchar) as headshot_url,
        cast(current_attributes.is_on_current_roster as boolean) as is_on_current_roster,
        cast(current_attributes.last_game_team_id as integer) as last_game_team_id,
        cast(current_attributes.height_inches as integer) as height_inches,
        cast(current_attributes.weight_lbs as integer) as weight_lbs,
        cast(current_attributes.birth_date as date) as birth_date,
        cast(current_attributes.birth_country as varchar) as birth_country,
        cast(current_attributes.experience_years as integer) as experience_years,
        -- The snapshot only starts recording when it first runs. Treat each player's first
        -- version as valid from the beginning of time so earlier games still join to it.
        cast(
            case
                when
                    snapshot.dbt_valid_from
                    = min(snapshot.dbt_valid_from) over (partition by snapshot.player_id)
                    then timestamp '1900-01-01'
                else snapshot.dbt_valid_from
            end as timestamp
        ) as valid_from,
        cast(snapshot.dbt_valid_to as timestamp) as valid_to,
        snapshot.dbt_valid_to is null as is_current
    from snapshot
    left join current_attributes
        on snapshot.player_id = current_attributes.player_id

)

select * from final
