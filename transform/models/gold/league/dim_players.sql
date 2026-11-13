{#-
    One row per player version (type 2). Join facts on player_id with is_current for today's
    attributes, or on player_id and the fact date between valid_from and valid_to for history.
    A player's first version is valid from 1900-01-01 (see the valid_from comment).
-#}

with

snapshot as (

    select * from {{ ref('snap_players') }}

),

final as (

    select
        cast(dbt_scd_id as varchar) as player_version_id,
        cast(player_id as integer) as player_id,
        cast(player_name as varchar) as player_name,
        cast(player_short_name as varchar) as player_short_name,
        cast(team_id as integer) as team_id,
        cast(jersey_number as varchar) as jersey_number,
        cast(position as varchar) as position,
        cast(headshot_url as varchar) as headshot_url,
        -- The snapshot only starts recording when it first runs. Treat each player's first
        -- version as valid from the beginning of time so earlier games still join to it.
        cast(
            case
                when dbt_valid_from = min(dbt_valid_from) over (partition by player_id)
                    then timestamp '1900-01-01'
                else dbt_valid_from
            end as timestamp
        ) as valid_from,
        cast(dbt_valid_to as timestamp) as valid_to,
        dbt_valid_to is null as is_current
    from snapshot

)

select * from final
