-- Reconciliación: cada período debe tener la misma cantidad de viajes y el mismo
-- total facturado en SILVER (válidos) y en GOLD. Devuelve filas si hay diferencias.
with silver as (
    select _source_period, count(*) as trips, sum(total_amount) as revenue
    from {{ ref('slv_yellow_trips') }}
    group by 1
),

gold as (
    select _source_period, count(*) as trips, sum(total_amount) as revenue
    from {{ ref('fct_trips') }}
    group by 1
)

select coalesce(s._source_period, g._source_period) as _source_period,
       s.trips as silver_trips, g.trips as gold_trips,
       s.revenue as silver_revenue, g.revenue as gold_revenue
from silver as s
full outer join gold as g on s._source_period = g._source_period
where s.trips is distinct from g.trips
   or s.revenue is distinct from g.revenue
