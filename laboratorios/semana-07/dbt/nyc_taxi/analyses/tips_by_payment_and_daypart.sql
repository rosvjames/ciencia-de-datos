-- Propina promedio (% sobre tarifa) por forma de pago y franja horaria.
select
    p.payment_type_name,
    t.day_part,
    count(*)                                                    as trips,
    avg(f.tip_amount / nullif(f.fare_amount, 0)) * 100          as avg_tip_pct
from {{ ref('fct_trips') }} as f
join {{ ref('dim_payment_type') }} as p on f.payment_type_key = p.payment_type_key
join {{ ref('dim_time') }}         as t on f.pickup_time_key = t.time_key
where f.is_fare_reliable
group by 1, 2
order by 1, 2
