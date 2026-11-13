{#-
    One row per player version (type 2). Join facts on player_id with is_current for today's
    attributes, or on player_id and the fact date between valid_from and valid_to for history.
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
        cast(dbt_valid_from as timestamp) as valid_from,
        cast(dbt_valid_to as timestamp) as valid_to,
        dbt_valid_to is null as is_current
    from snapshot

)

select * from final
