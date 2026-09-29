-- Viajes, ingreso y ticket promedio por mes y borough de origen.
select
    d.year_month,
    l.borough                       as pickup_borough,
    count(*)                        as trips,
    sum(f.total_amount)             as revenue,
    avg(f.total_amount)             as avg_ticket,
    avg(f.trip_distance)            as avg_distance_mi
from {{ ref('fct_trips') }} as f
join {{ ref('dim_date') }}     as d on f.pickup_date_key = d.date_key
join {{ ref('dim_location') }} as l on f.pickup_location_key = l.location_key
group by 1, 2
order by 1, 3 desc
