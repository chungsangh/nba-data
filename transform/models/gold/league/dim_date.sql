{#- One row per calendar day across the seasons in scope. MetricFlow uses it as the time spine. -#}

with

spine as (

    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('" ~ var('date_spine_start') ~ "' as date)",
        end_date="cast('" ~ var('date_spine_end') ~ "' as date)"
    ) }}

),

final as (

    select
        cast(date_day as date) as date_day,
        cast(dayname(date_day) as varchar) as day_name,
        cast(isodow(date_day) as integer) as day_of_week,
        cast(isodow(date_day) in (6, 7) as boolean) as is_weekend,
        cast(date_trunc('week', date_day) as date) as week_start_date,
        cast(date_trunc('month', date_day) as date) as month_start_date,
        -- ESPN season label: the season that starts in October is labelled by its end year
        cast(
            case when month(date_day) >= 8 then year(date_day) + 1 else year(date_day) end
            as integer
        ) as season
    from spine

)

select * from final
